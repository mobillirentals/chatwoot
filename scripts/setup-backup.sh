#!/bin/bash
# =============================================================
# Setup inicial do backup automático na VM de produção
# Executar UMA VEZ como root ou com sudo na VM:
#   sudo bash scripts/setup-backup.sh
# Lê credenciais de /opt/chatwoot/.env.production
# =============================================================
set -euo pipefail

ENV_FILE="/opt/chatwoot/.env.production"
SCRIPTS_DIR="/opt/chatwoot/scripts"
BACKUP_SCRIPT="$SCRIPTS_DIR/backup-db.sh"
LOG_FILE="/var/log/chatwoot-backup.log"
BACKUP_CONTAINER="chatwoot-backups"

echo "=== Setup do backup automático ==="

# Carrega credenciais Azure do .env.production
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERRO: $ENV_FILE não encontrado. Copie o arquivo antes de rodar este script." >&2
  exit 1
fi
# shellcheck disable=SC1090
set -o allexport; source "$ENV_FILE"; set +o allexport

# 1. Instala Azure CLI se não tiver
if ! command -v az &>/dev/null; then
  echo ">> Instalando Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash
else
  echo ">> Azure CLI já instalado: $(az version --query '"azure-cli"' -o tsv)"
fi

# 2. Cria container de backups no Azure Blob (idempotente)
echo ">> Criando container '$BACKUP_CONTAINER' no Azure Blob..."
az storage container create \
  --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
  --account-key "$AZURE_STORAGE_ACCESS_KEY" \
  --name "$BACKUP_CONTAINER" \
  --output none 2>/dev/null || true
echo ">> Container pronto."

# 3. Copia o script para a VM
echo ">> Instalando script de backup em $BACKUP_SCRIPT..."
mkdir -p "$SCRIPTS_DIR"
cp "$(dirname "$0")/backup-db.sh" "$BACKUP_SCRIPT"
chmod +x "$BACKUP_SCRIPT"

# 4. Cria arquivo de log com permissão correta
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# 5. Configura cron (2h da manhã, todo dia)
CRON_JOB="0 2 * * * $BACKUP_SCRIPT >> $LOG_FILE 2>&1"
CRONTAB_CURRENT=$(crontab -l 2>/dev/null || true)

if echo "$CRONTAB_CURRENT" | grep -q "$BACKUP_SCRIPT"; then
  echo ">> Cron já configurado."
else
  (echo "$CRONTAB_CURRENT"; echo "$CRON_JOB") | crontab -
  echo ">> Cron configurado: $CRON_JOB"
fi

# 6. Roda um backup imediato para validar
echo ""
echo ">> Rodando backup de validação agora..."
bash "$BACKUP_SCRIPT"

echo ""
echo "=== Setup concluído! ==="
echo "   Script:   $BACKUP_SCRIPT"
echo "   Log:      $LOG_FILE"
echo "   Cron:     todo dia às 02:00"
echo "   Retenção: 7 dias"
echo "   Destino:  Azure Blob '$BACKUP_CONTAINER'"
echo ""
echo "Para verificar backups:"
echo "  az storage blob list --account-name \$AZURE_STORAGE_ACCOUNT_NAME --account-key \$AZURE_STORAGE_ACCESS_KEY --container-name $BACKUP_CONTAINER --output table"
