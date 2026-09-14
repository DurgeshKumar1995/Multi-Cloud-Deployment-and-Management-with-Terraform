locals {
  name = "${var.name_prefix}-${var.environment}"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "multicloud-terraform"
  }
  required_services = toset([
    "compute.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "main" {
  name                    = "${local.name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "application" {
  name          = "${local.name}-application"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.30.1.0/24"
}

resource "google_compute_firewall" "health_and_http" {
  name    = "${local.name}-health-http"
  project = var.project_id
  network = google_compute_network.main.name

  direction     = "INGRESS"
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["${local.name}-application"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.container_port)]
  }
}

resource "google_compute_instance_template" "application" {
  name_prefix  = "${local.name}-"
  project      = var.project_id
  machine_type = "e2-micro"
  tags         = ["${local.name}-application"]
  labels       = local.labels

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-balanced"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.application.id

    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    container_image = var.container_image
    container_port  = var.container_port
    region          = var.region
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "application" {
  name               = "${local.name}-mig"
  project            = var.project_id
  region             = var.region
  base_instance_name = "${local.name}-app"
  target_size        = 2

  distribution_policy_zones = [for zone in var.zones : "projects/${var.project_id}/zones/${zone}"]

  version {
    instance_template = google_compute_instance_template.application.id
  }

  named_port {
    name = "http"
    port = var.container_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.application.id
    initial_delay_sec = 180
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 1
    max_unavailable_fixed        = 0
    replacement_method           = "SUBSTITUTE"
    instance_redistribution_type = "PROACTIVE"
  }
}

resource "google_compute_health_check" "application" {
  name                = "${local.name}-health"
  project             = var.project_id
  check_interval_sec  = 15
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.container_port
    request_path = var.health_check_path
  }
}

resource "google_compute_backend_service" "application" {
  name                  = "${local.name}-backend"
  project               = var.project_id
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.application.id]

  backend {
    group           = google_compute_region_instance_group_manager.application.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1
  }
}

resource "google_compute_url_map" "application" {
  name            = "${local.name}-url-map"
  project         = var.project_id
  default_service = google_compute_backend_service.application.id
}

resource "google_compute_target_http_proxy" "application" {
  name    = "${local.name}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.application.id
}

resource "google_compute_global_address" "application" {
  name    = "${local.name}-ip"
  project = var.project_id
}

resource "google_compute_global_forwarding_rule" "application" {
  name                  = "${local.name}-http"
  project               = var.project_id
  ip_address            = google_compute_global_address.application.id
  port_range            = "80"
  target                = google_compute_target_http_proxy.application.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_storage_bucket" "backup" {
  name                        = "${var.project_id}-${local.name}-backup"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  labels                      = local.labels

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

resource "google_monitoring_notification_channel" "email" {
  count = var.alert_email == "" ? 0 : 1

  project      = var.project_id
  display_name = "Multicloud project email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.required]
}

resource "google_monitoring_alert_policy" "instance_cpu" {
  display_name = "${local.name} high CPU"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "VM CPU above 80 percent"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.alert_email == "" ? [] : [google_monitoring_notification_channel.email[0].name]

  depends_on = [google_project_service.required]
}

resource "google_project_service" "sql" {
  count = var.enable_database ? 1 : 0

  project            = var.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_sql_database_instance" "database" {
  count = var.enable_database ? 1 : 0

  name             = "${local.name}-postgres"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
    }

    user_labels = local.labels
  }

  deletion_protection = true
  depends_on          = [google_project_service.sql]
}

resource "google_sql_user" "application" {
  count = var.enable_database ? 1 : 0

  project  = var.project_id
  instance = google_sql_database_instance.database[0].name
  name     = var.database_admin_username
  password = var.database_admin_password
}
