data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "multicloud-terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name}-public-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = "${local.name}-public" })
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "load_balancer" {
  name_prefix = "${local.name}-alb-"
  description = "Public HTTP ingress to the multi-cloud demo"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "application" {
  name_prefix = "${local.name}-app-"
  description = "Application traffic from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Application traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-app" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "application" {
  count = 2

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.application.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    container_image = var.container_image
    container_port  = var.container_port
    region          = var.region
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_size = 10
    volume_type = "gp3"
  }

  tags = merge(local.tags, { Name = "${local.name}-app-${count.index + 1}" })
}

resource "aws_lb" "application" {
  name                       = substr("${local.name}-alb", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.load_balancer.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true

  tags = local.tags
}

resource "aws_lb_target_group" "application" {
  name        = substr("${local.name}-app", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    matcher             = "200-399"
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "application" {
  count = 2

  target_group_arn = aws_lb_target_group.application.arn
  target_id        = aws_instance.application[count.index].id
  port             = var.container_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application.arn
  }
}

resource "aws_s3_bucket" "backup" {
  bucket_prefix = "${local.name}-backup-"
  force_destroy = false
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "One or more AWS application targets are unhealthy."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.application.arn_suffix
    TargetGroup  = aws_lb_target_group.application.arn_suffix
  }

  tags = local.tags
}

resource "aws_security_group" "database" {
  count = var.enable_database ? 1 : 0

  name_prefix = "${local.name}-db-"
  description = "PostgreSQL from application instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from application"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }

  tags = merge(local.tags, { Name = "${local.name}-db" })
}

resource "aws_db_subnet_group" "database" {
  count = var.enable_database ? 1 : 0

  name       = "${local.name}-db"
  subnet_ids = aws_subnet.public[*].id
  tags       = local.tags
}

resource "aws_db_instance" "database" {
  count = var.enable_database ? 1 : 0

  identifier                  = "${local.name}-postgres"
  engine                      = "postgres"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  username                    = "multicloudadmin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.database[0].name
  vpc_security_group_ids      = [aws_security_group.database[0].id]
  publicly_accessible         = false
  backup_retention_period     = 7
  deletion_protection         = false
  skip_final_snapshot         = true
  apply_immediately           = true
  tags                        = local.tags
}

