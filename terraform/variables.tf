variable "subscription_id" {
  description = "ID da assinatura Azure (Portal → Assinaturas)"
  type        = string
}

variable "location" {
  description = "Região Azure onde os recursos serão criados"
  type        = string
  default     = "brazilsouth"
}

variable "vm_size" {
  description = <<-EOT
    Tamanho da VM:
      Standard_B2s    → 2 vCPU /  4 GB RAM  (dev/teste — mais barato)
      Standard_D2s_v3 → 2 vCPU /  8 GB RAM  (produção pequena — recomendado)
      Standard_D4s_v3 → 4 vCPU / 16 GB RAM  (produção com mais carga)
  EOT
  type        = string
  default     = "Standard_D2s_v3"
}

variable "os_disk_size_gb" {
  description = "Tamanho do disco da VM em GB (mínimo 30, recomendado 64)"
  type        = number
  default     = 64
}

variable "admin_username" {
  description = "Usuário SSH da VM"
  type        = string
  default     = "chatwoot"
}

variable "ssh_public_key" {
  description = "Conteúdo da chave pública SSH (ex: conteúdo de ~/.ssh/id_rsa.pub)"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Domínio público do Chatwoot"
  type        = string
  default     = "chat.mobillirentals.com.br"
}

variable "letsencrypt_email" {
  description = "E-mail para notificações do Let's Encrypt"
  type        = string
  default     = "ti@mobillirentals.com.br"
}
