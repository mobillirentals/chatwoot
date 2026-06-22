output "vm_public_ip" {
  description = "IP público da VM — crie o registro DNS: A chat.mobillirentals.com.br → este IP"
  value       = azurerm_public_ip.main.ip_address
}

output "ssh_command" {
  description = "Comando SSH para conectar à VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "storage_account_name" {
  description = "AZURE_STORAGE_ACCOUNT_NAME — preencher no .env.production"
  value       = azurerm_storage_account.main.name
}

output "storage_access_key" {
  description = "AZURE_STORAGE_ACCESS_KEY — preencher no .env.production (use: terraform output -raw storage_access_key)"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "next_steps" {
  description = "Roteiro pós-apply"
  value       = <<-EOT

    ════════════════════════════════════════════════════════
     ✅  Infraestrutura criada com sucesso!
    ════════════════════════════════════════════════════════

    1. REGISTRO DNS
       Crie um registro A no painel do seu provedor de domínio:
         A  chat.mobillirentals.com.br  →  ${azurerm_public_ip.main.ip_address}
       (aguarde a propagação antes de emitir o certificado SSL)

    2. VARIÁVEIS DE ARMAZENAMENTO
       Execute para obter a chave do storage:
         terraform output -raw storage_access_key

       Preencha no .env.production:
         AZURE_STORAGE_ACCOUNT_NAME = ${azurerm_storage_account.main.name}
         AZURE_STORAGE_ACCESS_KEY   = <saída do comando acima>

    3. AGUARDE O BOOTSTRAP DA VM (≈ 3–5 min)
       O cloud-init instala Docker e configura UFW automaticamente.
       Verifique quando terminar:
         ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address} "cloud-init status"

    4. COPIE OS ARQUIVOS PARA A VM
         scp -r \
           ./nginx \
           ./docker-compose.production.yaml \
           ./.env.production \
           ${var.admin_username}@${azurerm_public_ip.main.ip_address}:/opt/chatwoot/

    5. CERTIFICADO SSL (na VM, após DNS propagar)
         ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}
         sudo /opt/chatwoot/scripts/certbot-init.sh

    6. PRIMEIRO DEPLOY
         ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}
         cd /opt/chatwoot
         docker compose -f docker-compose.production.yaml run --rm rails \
           bundle exec rails db:chatwoot_prepare
         docker compose -f docker-compose.production.yaml up -d

    ════════════════════════════════════════════════════════
  EOT
}
