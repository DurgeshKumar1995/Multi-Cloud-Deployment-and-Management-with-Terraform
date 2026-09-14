data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "multicloud-terraform"
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet" "application" {
  name                 = "application"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_network_security_group" "application" {
  name                = "${local.name}-app-nsg"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  security_rule {
    name                       = "AllowLoadBalancedApplication"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.container_port)
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "application" {
  subnet_id                 = azurerm_subnet.application.id
  network_security_group_id = azurerm_network_security_group.application.id
}

resource "azurerm_public_ip" "load_balancer" {
  name                = "${local.name}-public-ip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${local.name}-${random_string.suffix.result}"
  tags                = local.tags
}

resource "azurerm_lb" "application" {
  name                = "${local.name}-lb"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.load_balancer.id
  }
}

resource "azurerm_lb_backend_address_pool" "application" {
  name            = "application"
  loadbalancer_id = azurerm_lb.application.id
}

resource "azurerm_lb_probe" "application" {
  name                = "http-health"
  loadbalancer_id     = azurerm_lb.application.id
  protocol            = "Http"
  port                = var.container_port
  request_path        = var.health_check_path
  interval_in_seconds = 15
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  name                           = "http"
  loadbalancer_id                = azurerm_lb.application.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = var.container_port
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.application.id]
  probe_id                       = azurerm_lb_probe.application.id
  disable_outbound_snat          = false
}

resource "azurerm_network_interface" "application" {
  count = 2

  name                = "${local.name}-nic-${count.index + 1}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.application.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "application" {
  count = 2

  network_interface_id    = azurerm_network_interface.application[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.application.id
}

resource "azurerm_linux_virtual_machine" "application" {
  count = 2

  name                            = "${local.name}-vm-${count.index + 1}"
  resource_group_name             = data.azurerm_resource_group.main.name
  location                        = data.azurerm_resource_group.main.location
  size                            = "Standard_B1s"
  zone                            = tostring(count.index + 1)
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.application[count.index].id]
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yml.tftpl", {
    container_image = var.container_image
    container_port  = var.container_port
    location        = var.location
  }))
  tags = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

resource "azurerm_storage_account" "backup" {
  name                            = substr(replace("${var.name_prefix}${var.environment}${random_string.suffix.result}", "-", ""), 0, 24)
  resource_group_name             = data.azurerm_resource_group.main.name
  location                        = data.azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  tags                            = local.tags
}

resource "azurerm_storage_container" "backup" {
  name                  = "backups"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

resource "azurerm_monitor_action_group" "alerts" {
  count = var.alert_email == "" ? 0 : 1

  name                = "${local.name}-alerts"
  resource_group_name = data.azurerm_resource_group.main.name
  short_name          = "mcloud"
  tags                = local.tags

  email_receiver {
    name          = "project-email"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "${local.name}-high-cpu"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine.application[0].id]
  description         = "Azure application VM CPU is above 80 percent."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  dynamic "action" {
    for_each = var.alert_email == "" ? [] : [1]
    content {
      action_group_id = azurerm_monitor_action_group.alerts[0].id
    }
  }
}

resource "azurerm_subnet" "database" {
  count = var.enable_database ? 1 : 0

  name                 = "database"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.2.0/24"]

  delegation {
    name = "postgresql"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "database" {
  count = var.enable_database ? 1 : 0

  name                = "${local.name}.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "database" {
  count = var.enable_database ? 1 : 0

  name                  = "${local.name}-postgres"
  private_dns_zone_name = azurerm_private_dns_zone.database[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  resource_group_name   = data.azurerm_resource_group.main.name
  tags                  = local.tags
}

resource "azurerm_postgresql_flexible_server" "database" {
  count = var.enable_database ? 1 : 0

  name                   = "${local.name}-postgres-${random_string.suffix.result}"
  resource_group_name    = data.azurerm_resource_group.main.name
  location               = data.azurerm_resource_group.main.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.database[0].id
  private_dns_zone_id    = azurerm_private_dns_zone.database[0].id
  administrator_login    = var.database_admin_username
  administrator_password = var.database_admin_password
  zone                   = "1"
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  backup_retention_days  = 7
  tags                   = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.database]
}

