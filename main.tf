resource "azurerm_resource_group" "rg" {
  name      = var.rg
  location  = var.location
}

resource "azurerm_virtual_network" "network" {
  name                = "vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet_app" {
  name                 = "subnet_app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "nic_app" {
  name                = "nic_app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "nic_app_config"
    subnet_id                     = azurerm_subnet.subnet_app.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_security_group" "nsg_app" {
  name                = "nsg_app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "assoc-nic-nsg-app" {
  network_interface_id      = azurerm_network_interface.nic_app.id
  network_security_group_id = azurerm_network_security_group.nsg_app.id
}

resource "azurerm_linux_virtual_machine" "vm_app" {
  name                  = "vm-app"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic_app.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "disk_app"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-11"
    sku       = "11"
    version   = "latest"
  }

  custom_data                     = data.cloudinit_config.cloud-init.rendered
  admin_username                  = "celia"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "celia"
    public_key = azurerm_ssh_public_key.ssh_key.public_key
  }
}

resource "azurerm_ssh_public_key" "ssh_key" {
  name                = "ssh_key_admin"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  public_key          = file("C:/Users/utilisateur/.ssh/id_rsa.pub") 
}

resource "azurerm_subnet" "subnet_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "public_ip_bastion" {
  name                = "public_ip_bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_bastion_host" "bastion" {
  name                = "bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tunneling_enabled   = true
  ip_connect_enabled  = true
  sku                 = "Standard"

  ip_configuration {
    name                 = "bastion_ip"
    subnet_id            = azurerm_subnet.subnet_bastion.id
    public_ip_address_id = azurerm_public_ip.public_ip_bastion.id
  }
}

resource "azurerm_public_ip" "public_ip_nat" {
  name                = "public-ip-nat"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "nat_gw" {
  name                    = "nat-gw"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  sku_name                = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "gw_ip_a" {
  nat_gateway_id       = azurerm_nat_gateway.nat_gw.id
  public_ip_address_id = azurerm_public_ip.public_ip_nat.id
}

resource "azurerm_subnet_nat_gateway_association" "gw_a" {
  subnet_id      = azurerm_subnet.subnet_app.id
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id
}

resource "azurerm_subnet" "subnet_gateway" {
  name                 = "subnet_gateway"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public_ip_gateway" {
  name                = "public_ip_gateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${lower(var.subdomain-prefix)}-${lower(var.rg)}"
}

resource "azurerm_application_gateway" "gateway" {
 name                = "gateway"
 resource_group_name = azurerm_resource_group.rg.name
 location            = azurerm_resource_group.rg.location

 sku {
   name     = "Standard_v2"
   tier     = "Standard_v2"
 }

 gateway_ip_configuration {
   name      = "ip-configuration"
   subnet_id = azurerm_subnet.subnet_gateway.id
 }

 frontend_port {
   name = "http"
   port = 80
 }

 frontend_ip_configuration {
   name                 = "front-ip"
   public_ip_address_id = azurerm_public_ip.public_ip_gateway.id
 }

 backend_address_pool {
   name = "backend_pool"
 }

 backend_http_settings {
   name                  = "http-settings"
   cookie_based_affinity = "Disabled"
   path                  = "/"
   port                  = 80
   protocol              = "Http"
   request_timeout       = 10
 }

 http_listener {
   name                           = "listener"
   frontend_ip_configuration_name = "front-ip"
   frontend_port_name             = "http"
   protocol                       = "Http"
 }

 request_routing_rule {
   name                       = "rule-1"
   rule_type                  = "Basic"
   http_listener_name         = "listener"
   backend_address_pool_name  = "backend_pool"
   backend_http_settings_name = "http-settings"
   priority                   = 100
 }

 autoscale_configuration {
   min_capacity = 1
 }
}

resource "azurerm_redis_cache" "redis" {
  name                = "${var.rg}-brief5"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  capacity            = 2
  family              = "C"
  sku_name            = "Standard"
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  redis_version       = 6
}

resource "azurerm_redis_firewall_rule" "vm_app" {
  name                = "vm_app"
  redis_cache_name    = azurerm_redis_cache.redis.name
  resource_group_name = azurerm_resource_group.rg.name
  start_ip            = azurerm_public_ip.public_ip_nat.ip_address
  end_ip              = azurerm_public_ip.public_ip_nat.ip_address
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "poolbackend" {
 network_interface_id    = azurerm_network_interface.nic_app.id
 ip_configuration_name   = "nic_app_config"
 backend_address_pool_id = tolist(azurerm_application_gateway.gateway.backend_address_pool).0.id
}

output "application-address" {
  value = "http://${azurerm_public_ip.public_ip_gateway.fqdn}"
}

