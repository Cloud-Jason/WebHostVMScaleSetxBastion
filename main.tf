terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "jc-rg" {
  name     = "jc-resources"
  location = "UK South"
  tags = {
    enviroment = "dev"
  }
}

resource "azurerm_virtual_network" "jc-vn" {
  name                = "jc-network"
  resource_group_name = azurerm_resource_group.jc-rg.name
  location            = azurerm_resource_group.jc-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    enviroment = "dev"
  }
}

resource "azurerm_subnet" "jc-subnet" {
  name                 = "jc-subnet"
  resource_group_name  = azurerm_resource_group.jc-rg.name
  virtual_network_name = azurerm_virtual_network.jc-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "jc-sg" {
  name                = "jc-sg"
  location            = azurerm_resource_group.jc-rg.location
  resource_group_name = azurerm_resource_group.jc-rg.name

  tags = {
    enviroment = "dev"
  }
}

resource "azurerm_network_security_rule" "jc-dev-rule" {
  name                        = "jc-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.jc-rg.name
  network_security_group_name = azurerm_network_security_group.jc-sg.name
}

resource "azurerm_subnet_network_security_group_association" "jc-sga" {
  subnet_id                 = azurerm_subnet.jc-subnet.id
  network_security_group_id = azurerm_network_security_group.jc-sg.id
}

resource "azurerm_public_ip" "jc-ip" {
  name                = "jc-ip-1"
  resource_group_name = azurerm_resource_group.jc-rg.name
  location            = azurerm_resource_group.jc-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_network_interface" "jc-nic" {
  name                = "jc-nic"
  location            = azurerm_resource_group.jc-rg.location
  resource_group_name = azurerm_resource_group.jc-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jc-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jc-ip.id
  }

  tags = {
    enviroment = "Dev"
  }
}

resource "azurerm_linux_virtual_machine" "jc-vm" {
  name                  = "jc-vm"
  resource_group_name   = azurerm_resource_group.jc-rg.name
  location              = azurerm_resource_group.jc-rg.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.jc-nic.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/jcazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os} linux-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/jcazurekey"
    })
    interpreter = ["Powershell", "-Command"]
  }

  tags = {
    enviroment = "dev"
  }
}

data "azurerm_public_ip" "jc-ip-data" {
    name = azurerm_public_ip.jc-ip.name
    resource_group_name = azurerm_resource_group.jc-rg.name
}

output "public_ip_address" {
    value = "${azurerm_linux_virtual_machine.jc-vm.name}: ${data.azurerm_public_ip.jc-ip-data.ip_address}"
}