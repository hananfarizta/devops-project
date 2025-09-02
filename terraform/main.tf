# terraform/main.tf

# --- Resource Group ---
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix_name}-rg"
  location = var.location
  tags     = var.tags
}

# --- Azure Container Registry (ACR) ---
resource "azurerm_container_registry" "acr" {
  name                = "${var.prefix_name}acr" # Nama harus unik global
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

# --- Log Analytics Workspace ---
resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix_name}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# --- Azure Kubernetes Service (AKS) ---
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix_name}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.dns_prefix != "" ? var.dns_prefix : var.prefix_name
  kubernetes_version  = "1.30.3" # Tentukan versi yang stabil

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.node_size
  }

  identity {
    type = "SystemAssigned"
  }

  # Integrasi dengan Log Analytics untuk Container Insights
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  tags = var.tags
}

# --- Role Assignment: AKS -> ACR ---
# Memberikan izin kepada Kubelet (identitas AKS) untuk menarik (pull) image dari ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}