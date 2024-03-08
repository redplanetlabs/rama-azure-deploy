###########################################################
# Variables and configuration
###########################################################

## Required vars

variable "cluster_name" { type = string }     # from rama-cluster.sh
variable "azure_public_key" { type = string } # from ~/.rama/auth.tfvars

# From rama.tfvars
variable "location" { type = string }
variable "username" { type = string }

variable "rama_source_path" { type = string }
variable "license_source_path" { type = string }
variable "zookeeper_url" { type = string }

variable "security_group_id" { type = string }
variable "subnet_id" { type = string }

variable "zookeeper_vm_image"  { type = string }
variable "conductor_vm_image"  { type = string }
variable "supervisor_vm_image" { type = string }

variable "zookeeper_size"  { type = string }
variable "conductor_size"  { type = string }
variable "supervisor_size" { type = string }

variable "supervisor_num_nodes" { type = number }

## Optional vars

variable "zookeeper_num_nodes" {
  type    = number
  default = 1
}

variable "supervisor_volume_size_gb" {
  type    = number
  default = 100
}

variable "use_private_ip" {
  type    = bool
  default = false
}

variable "private_ssh_key" {
  type    = string
  default = null
}

locals {
  zk_public_ips          = data.azurerm_public_ip.zk.*.ip_address
  zk_private_ips         = azurerm_linux_virtual_machine.zk.*.private_ip_address

  conductor_public_ip    = data.azurerm_public_ip.conductor.ip_address
  conductor_private_ip   = azurerm_linux_virtual_machine.conductor.private_ip_address

  supervisor_public_ips  = data.azurerm_public_ip.supervisor.*.ip_address
  supervisor_private_ips = azurerm_linux_virtual_machine.supervisor.*.private_ip_address

  home_dir    = "/home/${var.username}"
  systemd_dir = "/etc/systemd/system"
}

###########################################################
# Providers
###########################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
    cloudinit = {
      version = "~> 2.2.0"
    }
  }
}

provider "azurerm" {
  # This is only required when the User, Service Principal, or Identity running Terraform lacks 
  # the permissions to register Azure Resource Providers.
  skip_provider_registration = true 
  features {}
}

###########################################################
# Resource Groups
###########################################################

resource "azurerm_resource_group" "cluster" {
  name = var.cluster_name 
  location = var.location
}

###########################################################
# Zookeeper
###########################################################

###
# Networking
###

resource "azurerm_public_ip" "zk" {
  name                = "${var.cluster_name}-zk-public-ip-${count.index}"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  allocation_method   = "Dynamic"
  count               = var.zookeeper_num_nodes
  
  tags = {
    environment = "test"
  }
}

resource "azurerm_network_interface" "zk" {
  name                = "${var.cluster_name}-zk-nic-${count.index}"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  count               = var.zookeeper_num_nodes

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.zk[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "zk_association" {
  network_interface_id      = azurerm_network_interface.zk[count.index].id
  network_security_group_id = var.security_group_id
  count = var.zookeeper_num_nodes
}

###
# Virtual Machines
###

# TODO: Perhaps this should be an `azurerm_linux_virtual_machine_scale_set` instead?
resource "azurerm_linux_virtual_machine" "zk" {
  source_image_id     = var.zookeeper_vm_image
  size                = var.zookeeper_size
  count               = var.zookeeper_num_nodes

  name                = "${terraform.workspace}-zk-node-${count.index}"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  admin_username      = var.username
  network_interface_ids = [
    azurerm_network_interface.zk[count.index].id,
  ]

  # Secure Boot is required to boot from Gallery Image
  secure_boot_enabled = true
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb = 100
  }

  admin_ssh_key {
    username   = var.username
    public_key = file(var.azure_public_key)
  }
}

data "azurerm_public_ip" "zk" {
  name                = azurerm_public_ip.zk[count.index].name
  resource_group_name = azurerm_linux_virtual_machine.zk[count.index].resource_group_name
  count               = var.zookeeper_num_nodes
}

resource "null_resource" "zookeeper" {
  count = var.zookeeper_num_nodes

  connection {
    type        = "ssh"
    user        = var.username
    host        = data.azurerm_public_ip.zk[count.index].ip_address
    private_key = var.private_ssh_key != null ? file(var.private_ssh_key) : null
  }

  triggers = {
    zookeeper_ids = "${join(",", azurerm_linux_virtual_machine.zk.*.id)}"
  }

  provisioner "file" {
    content = templatefile("zookeeper/zookeeper.service", {
      username = var.username
    })
    destination = "${local.home_dir}/zookeeper.service"
  }

  provisioner "file" {
    source      = "zookeeper/setup.sh"
    destination = "${local.home_dir}/setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ${local.home_dir}/setup.sh",
      "${local.home_dir}/setup.sh ${var.zookeeper_url}"
    ]
  }

  provisioner "file" {
    content = templatefile("zookeeper/zoo.cfg", {
      num_servers    = var.zookeeper_num_nodes
      zk_private_ips = local.zk_private_ips
      server_index   = count.index
      username       = var.username
    })
    destination = "${local.home_dir}/zookeeper/conf/zoo.cfg"
  }

  provisioner "file" {
    content = templatefile("zookeeper/myid", {
      zkid = count.index + 1
    })
    destination = "${local.home_dir}/zookeeper/data/myid"
  }

  provisioner "remote-exec" {
    script = "zookeeper/start.sh"
  }
}

###########################################################
# Conductor
###########################################################

###
# Networking
###

resource "azurerm_public_ip" "conductor" {
  name                = "${var.cluster_name}-conductor-public-ip"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "conductor" {
  name                = "${var.cluster_name}-conductor-nic"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.conductor.id
  }
}

resource "azurerm_network_interface_security_group_association" "conductor_association" {
  network_interface_id      = azurerm_network_interface.conductor.id
  network_security_group_id = var.security_group_id
}

###
# Virtual Machines
###

resource "azurerm_linux_virtual_machine" "conductor" {
  source_image_id     = var.conductor_vm_image
  size                = var.conductor_size

  name                = "${terraform.workspace}-conductor-node"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  admin_username      = var.username
  network_interface_ids = [
    azurerm_network_interface.conductor.id,
  ]

  # Secure Boot is required to boot from Gallery Image
  secure_boot_enabled = true
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb = 100
  }

  admin_ssh_key {
    username   = var.username
    public_key = file(var.azure_public_key)
  }
}

data "azurerm_public_ip" "conductor" {
  name                = azurerm_public_ip.conductor.name
  resource_group_name = azurerm_linux_virtual_machine.conductor.resource_group_name
}

resource "null_resource" "conductor" {
  connection {
    type        = "ssh"
    user        = var.username
    host        = local.conductor_public_ip
    private_key = var.private_ssh_key != null ? file(var.private_ssh_key) : null
  }

  triggers = {
    conductor_id = "${azurerm_linux_virtual_machine.conductor.id}"
  }

  provisioner "remote-exec" {
    # Make sure SSH is up and available on the server before trying anything else
    inline = ["ls"]
  }

  provisioner "file" {
    content = templatefile("setup-disks.sh", { username = var.username })
    destination = "${local.home_dir}/setup-disks.sh"
  }

  provisioner "remote-exec" {
    inline = [ "chmod +x setup-disks.sh", "sudo ./setup-disks.sh" ]
  }

  provisioner "file" {
    content = templatefile("conductor/rama.yaml", {
        zk_private_ips = azurerm_linux_virtual_machine.zk.*.private_ip_address
    })
    destination = "/data/rama/rama.yaml"
  } 

  provisioner "file" {
    content = templatefile("systemd-service-template.service", {
      description = "Rama Conductor",
      command     = "conductor"
    })
    destination = "${local.home_dir}/conductor.service"
  }

  provisioner "file" {
    content = file("${var.license_source_path}")
    destination = "/data/rama/license/team-license.yaml"
  }

  provisioner "file" {
    content = templatefile("conductor/unpack-rama.sh", { username = var.username }) 
    destination = "/data/rama/unpack-rama.sh"
  }

  provisioner "file" {
    content = templatefile("conductor/start.sh", { username = var.username })
    destination = "${local.home_dir}/start.sh" 
  }

  provisioner "local-exec" {
    when    = create
    command = "./upload_rama.sh ${var.private_ssh_key} ${var.rama_source_path} ${var.username} ${local.conductor_public_ip}"
  }

  provisioner "remote-exec" {
    inline = [
      "cd /data/rama",
      "chmod +x unpack-rama.sh",
      "./unpack-rama.sh"
    ]
  }
  
  provisioner "remote-exec" {
    inline = [ "chmod +x start.sh", "sudo ./start.sh" ] 
  }
}

###########################################################
# Supervisors
###########################################################

###
# Networking
###

resource "azurerm_public_ip" "supervisor" {
  name                = "${var.cluster_name}-supervisor-public-ip-${count.index}"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  allocation_method   = "Dynamic"
  count               = var.supervisor_num_nodes
}

resource "azurerm_network_interface" "supervisor" {
  name                = "${var.cluster_name}-supervisor-nic-${count.index}"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  count               = var.supervisor_num_nodes

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.supervisor[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "supervisor" {
  network_interface_id      = azurerm_network_interface.supervisor[count.index].id
  network_security_group_id = var.security_group_id
  count = var.supervisor_num_nodes
}

###
# Virtual Machines
###

# TODO: Perhaps this should be an `azurerm_linux_virtual_machine_scale_set` instead?
resource "azurerm_linux_virtual_machine" "supervisor" {
  source_image_id     = var.supervisor_vm_image
  size                = var.supervisor_size
  count               = var.supervisor_num_nodes

  name                = "${terraform.workspace}-supervisor-node-${count.index}"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  admin_username      = var.username
  network_interface_ids = [
    azurerm_network_interface.supervisor[count.index].id,
  ]

  # Secure Boot is required to boot from Gallery Image
  secure_boot_enabled = true
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb = var.supervisor_volume_size_gb
  }

  admin_ssh_key {
    username   = var.username
    public_key = file(var.azure_public_key)
  }
}

data "azurerm_public_ip" "supervisor" {
  name                = azurerm_public_ip.supervisor[count.index].name
  resource_group_name = azurerm_linux_virtual_machine.supervisor[count.index].resource_group_name
  count               = var.supervisor_num_nodes
}

resource "null_resource" "supervisor" {
  count = var.supervisor_num_nodes

  connection {
    type        = "ssh"
    user        = var.username
    host        = data.azurerm_public_ip.supervisor[count.index].ip_address
    private_key = var.private_ssh_key != null ? file(var.private_ssh_key) : null
  }

  triggers = {
    supervisor_ids = "${join(",", azurerm_linux_virtual_machine.supervisor.*.id)}"
  }

  provisioner "file" {
    content = templatefile("setup-disks.sh", { username = var.username })
    destination = "${local.home_dir}/setup-disks.sh"
  }
  
  provisioner "file" {
    content = templatefile("download_rama.sh", { conductor_ip = local.conductor_private_ip })
    destination = "${local.home_dir}/download_rama.sh"
  }

  provisioner "remote-exec" {
    inline = [ "chmod +x setup-disks.sh", "sudo ./setup-disks.sh" ]
  }

  provisioner "remote-exec" {
    inline = [ "chmod +x download_rama.sh", "sudo ./download_rama.sh" ]
  }

  provisioner "file" {
    content = templatefile("supervisor/rama.yaml", {
      zk_private_ips       = local.zk_private_ips
      conductor_private_ip = local.conductor_private_ip
    })
    destination = "${local.home_dir}/rama.yaml"
  }

  provisioner "file" {
    content = templatefile("systemd-service-template.service", {
      description = "Rama Supervisor"
      command     = "supervisor"
    })
    destination = "${local.home_dir}/supervisor.service"
  }

  provisioner "file" {
    content = templatefile("supervisor/start.sh", {
      username = var.username
      private_ip = azurerm_linux_virtual_machine.supervisor[count.index].private_ip_address
    })
    destination = "${local.home_dir}/start.sh"
  }

  provisioner "remote-exec" {
    inline = [ "chmod +x start.sh", "sudo ./start.sh" ] 
  }
}

###########################################################
# Local State
###########################################################

# zookeeper.servers is currently localhost...

###
# Setup local to allow `rama-my-cluster` commands
###
resource "null_resource" "local" {
  # Render to local file on machine
  # https://github.com/hashicorp/terraform/issues/8090#issuecomment-291823613
  provisioner "local-exec" {
    command = format(
      "cat <<\"EOF\" > \"%s\"\n%s\nEOF",
      "/tmp/deployment.yaml",
      templatefile("local.yaml", {
        zk_private_ips       = local.zk_private_ips
        conductor_private_ip = local.conductor_private_ip
      })
    )
  }
}

###########################################################
# Outputs
###########################################################

output "zookeeper_ips" {
  value = local.zk_public_ips
}

output "conductor_ip" {
  value = local.conductor_public_ip
}

output "conductor_ui" {
  value = "http://${local.conductor_public_ip}:8888"
}

output "supervisor_ids" {
  value = local.supervisor_public_ips
}