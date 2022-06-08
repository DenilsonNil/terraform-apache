terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {}
}

## Resource group
resource "azurerm_resource_group" "rg-aulainfra" {
  name     = "aulainfracloudterra"
  location = "eastus"
}

## Virtual network
resource "azurerm_virtual_network" "vnet-aulainfra" {
  name                = "vnet"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Production"
    destination : "Exercício"
  }
}

#Subnet
resource "azurerm_subnet" "sub-aulainfra" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.rg-aulainfra.name
  virtual_network_name = azurerm_virtual_network.vnet-aulainfra.name
  address_prefixes     = ["10.0.1.0/24"]
}

#public ip
resource "azurerm_public_ip" "ip-aulainfra" {
  name                = "publicip"
  resource_group_name = azurerm_resource_group.rg-aulainfra.name
  location            = azurerm_resource_group.rg-aulainfra.location
  allocation_method   = "Static"
}

#Firewall
resource "azurerm_network_security_group" "nsg-aulainfra" {
  name                = "nsg"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name

  #Allowing SSH
  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  #Allowing PORT
  security_rule {
    name                       = "web"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#Network interface
resource "azurerm_network_interface" "nic-aulainfra" {
  name                = "nic"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name

  ip_configuration {
    name                          = "nic-ip"
    subnet_id                     = azurerm_subnet.sub-aulainfra.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-aulainfra.id
  }
}

#Connect firewall with the network interface
resource "azurerm_network_interface_security_group_association" "nic-nsg-aulainfra" {
  network_interface_id      = azurerm_network_interface.nic-aulainfra.id
  network_security_group_id = azurerm_network_security_group.nsg-aulainfra.id
}

#VM Storage
resource "azurerm_storage_account" "sa-aulainfra" {
  name                     = "saaulainfra"
  resource_group_name      = azurerm_resource_group.rg-aulainfra.name
  location                 = azurerm_resource_group.rg-aulainfra.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "staging"
  }
}

#Linux VM
resource "azurerm_linux_virtual_machine" "vm-aulainfra" {
  name                = "vm"
  resource_group_name = azurerm_resource_group.rg-aulainfra.name
  location            = azurerm_resource_group.rg-aulainfra.location
  size                = "Standard_DS1_V2"

  network_interface_ids = [
    azurerm_network_interface.nic-aulainfra.id,
  ]

  admin_username                  = var.user
  admin_password                  = var.password
  disable_password_authentication = false

  os_disk {
    name                 = "mydisc"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sa-aulainfra.primary_blob_endpoint
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

## ssh adminuser@publicip
## type the password

# Null resource to install web server
data "azurerm_public_ip" "ip-aulainfra-data" {
  name                = azurerm_public_ip.ip-aulainfra.name
  resource_group_name = azurerm_resource_group.rg-aulainfra.name
}


resource "null_resource" "install-webserver" {
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip-aulainfra-data.ip_address
    user     = var.user
    password = var.password
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2"
    ]
  }
  # The VM needs to be on
  depends_on = [
    azurerm_linux_virtual_machine.vm-aulainfra
  ]
}

variable "user" {
  description = "usuario da máquina"
  type = string
}

variable "password" {
  description = "senha do usuário"
  type = string
}

resource "null_resource" "upload-app" {
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip-aulainfra-data.ip_address
    user     = var.user
    password = var.password
  }

  provisioner "file" {
    source =  "app"
    destination = "/home/adminuser"
  }
  # The VM needs to be on
  depends_on = [
    azurerm_linux_virtual_machine.vm-aulainfra
  ]
}