##############################################################################
# Terraform Configuration - Lab Environment
#
# Provisions K3s cluster infrastructure on a single VM
# Designed for 2 vCPU / 8GB RAM constraints
##############################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Backend configuration for state management
  # Get this from the output of tfstate-bucket/main.tf
  backend "azurerm" {
    resource_group_name  = "extremelab-tfstate"
    storage_account_name = "extremelabtfstate91"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

##############################################################################
# Provider Configuration
##############################################################################

provider "azurerm" {
  features {}
}

##############################################################################
# Local Variables
##############################################################################

locals {
  cluster_name = "k3s-lab"
  environment  = "lab"

  # Azure configuration
  azure = {
    location = "southeastasia"
    vm_size  = "Standard_B2ms" # 2 vCPU, 8GB RAM
  }

  # Resource constraints
  node_resources = {
    cpu_limit    = "2000m"
    memory_limit = "7Gi" # Leave 1GB for OS
  }

  # K3s configuration
  k3s_version = "v1.30.0+k3s1"
  k3s_config = {
    disable = [
      "traefik",      # Using Kong instead
      "servicelb",    # Using MetalLB
      "local-storage" # Using custom storage provisioner
    ]
    write-kubeconfig-mode = "0644"
  }

  # Network configuration
  network = {
    vnet_cidr    = "10.0.0.0/16"
    subnet_cidr  = "10.0.1.0/24"
    pod_cidr     = "10.42.0.0/16"
    service_cidr = "10.43.0.0/16"
    cluster_dns  = "10.43.0.10"
  }

  # Tags for resource management
  common_tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "kubernetes-extreme-lab"
    Owner       = "platform-team"
  }
}

##############################################################################
# Azure Resource Group
##############################################################################

resource "azurerm_resource_group" "main" {
  name     = "${local.cluster_name}-rg"
  location = local.azure.location

  tags = local.common_tags
}

##############################################################################
# Network Module - Azure VNet and Subnet
##############################################################################

module "network" {
  source = "../../modules/networking"

  cluster_name        = local.cluster_name
  environment         = local.environment
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  vnet_cidr   = local.network.vnet_cidr
  subnet_cidr = local.network.subnet_cidr

  tags       = local.common_tags
  depends_on = [azurerm_resource_group.main]
}

#############################################################################
# VM Module - K3s Master Node
#############################################################################

module "vm" {
  source = "../../modules/vm"

  vm_name             = "${local.cluster_name}-master"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.subnet_id
  public_ip_enabled   = true

  # VM Configuration
  vm_size        = local.azure.vm_size
  admin_username = var.admin_username

  # SSH Key
  ssh_public_key = file(var.ssh_public_key_path)

  # OS Disk
  os_disk_type    = var.os_disk_type
  os_disk_size_gb = var.os_disk_size_gb

  # Ubuntu 22.04 LTS
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  image_version   = "latest"

  tags = merge(
    local.common_tags,
    {
      Role = "master"
    }
  )
  depends_on = [module.network]
}

##############################################################################
# K3s Cluster Module
##############################################################################

module "k3s_cluster" {
  source = "../../modules/k3s-cluster"

  cluster_name = local.cluster_name
  environment  = local.environment
  k3s_version  = local.k3s_version

  # Network configuration
  pod_cidr     = local.network.pod_cidr
  service_cidr = local.network.service_cidr
  cluster_dns  = local.network.cluster_dns

  # Disable default components
  disable_components = local.k3s_config.disable

  # Resource constraints
  node_cpu_limit    = local.node_resources.cpu_limit
  node_memory_limit = local.node_resources.memory_limit

  tags       = local.common_tags
  depends_on = [module.vm]
}

##############################################################################
# Local K3s Installation (Docker-based for lab)
##############################################################################

resource "null_resource" "k3s_installation" {
  depends_on = [module.k3s_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      echo "K3s cluster configuration generated"
      echo "Run: ansible-playbook -i ../../ansible/inventory/lab.ini ../../ansible/playbooks/k3s-install.yaml"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

##############################################################################
# Generate Ansible Inventory
##############################################################################

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../../ansible/inventory/lab.ini"
  content = templatefile("${path.module}/templates/inventory.tpl", {
    cluster_name              = local.cluster_name
    environment               = local.environment
    k3s_version               = local.k3s_version
    pod_cidr                  = local.network.pod_cidr
    service_cidr              = local.network.service_cidr
    cluster_dns               = local.network.cluster_dns
    k3s_server_manifests_dir  = "/var/lib/rancher/k3s/server/manifests"
    k3s_config_dir            = "/etc/rancher/k3s"
    enable_secrets_encryption = var.enable_secrets_encryption
    enable_audit_logging      = var.enable_audit_logging
    node_cpu_limit            = local.node_resources.cpu_limit
    node_memory_limit         = local.node_resources.memory_limit
    vm_name                   = module.vm.vm_name
    vm_public_ip              = module.vm.public_ip_address
    vm_user                   = module.vm.admin_username
  })

  file_permission = "0644"
}

##############################################################################
# Generate kubeconfig placeholder
##############################################################################

resource "local_file" "kubeconfig_readme" {
  filename = "${path.module}/kubeconfig-README.md"
  content  = <<-EOT
    # Kubeconfig Setup

    After K3s installation, kubeconfig will be available at:
    - Default: `/etc/rancher/k3s/k3s.yaml`
    - User: `~/.kube/config`

    ## Export kubeconfig:
    ```bash
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    ```

    ## Or copy to default location:
    ```bash
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    ```

    ## Verify:
    ```bash
    kubectl cluster-info
    kubectl get nodes
    ```
  EOT

  file_permission = "0644"
}
