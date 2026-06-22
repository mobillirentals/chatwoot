# Sufixo aleatório para garantir nome globalmente único (3–24 chars alfanumérico minúsculo)
resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_storage_account" "main" {
  name                     = "chatwoot${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

# Container privado para uploads do Chatwoot (avatares, anexos, etc.)
resource "azurerm_storage_container" "chatwoot" {
  name                  = "chatwoot"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}
