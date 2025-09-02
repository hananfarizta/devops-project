# terraform/variables.tf

variable "prefix_name" {
  type        = string
  description = "Prefix unik untuk semua nama resource (harus huruf kecil)."
}

variable "location" {
  type        = string
  description = "Lokasi Azure untuk men-deploy resource."
  default     = "Southeast Asia"
}

variable "tags" {
  type        = map(string)
  description = "Tag yang akan diterapkan pada semua resource."
  default     = {}
}

variable "node_count" {
  type        = number
  description = "Jumlah node dalam default node pool AKS."
  default     = 2
}

variable "node_size" {
  type        = string
  description = "Ukuran VM untuk node AKS."
  default     = "Standard_DS2_v2"
}

variable "acr_sku" {
  type        = string
  description = "SKU untuk Azure Container Registry."
  default     = "Standard"
}

variable "dns_prefix" {
  type        = string
  description = "DNS prefix untuk AKS cluster."
  default     = ""
}