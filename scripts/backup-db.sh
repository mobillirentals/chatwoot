#!/bin/bash
# =============================================================
# Backup automático dos bancos PostgreSQL → Azure Blob Storage
# Cron: 0 2 * * * /opt/chatwoot/scripts/backup-db.sh
# Lê credenciais de /opt/chatwoot/.env.production
# =============================================================
set -euo pipefail

# ── Carrega variáveis de ambiente ─────────────────────────────
ENV_FILE="/opt/chatwoot/.env.production"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERRO: $ENV_FILE não encontrado" >&2
  exit 1
fi
# shellcheck disable=SC1090
set -o allexport; source "$ENV_FILE"; set +o allexport

# ── Configuração ──────────────────────────────────────────────
BACKUP_CONTAINER="chatwoot-backups"
RETENTION_DAYS=7
DB_USER="cw_app"
DATABASES=("chatwoot_production" "typebot")
BACKUP_DIR="/tmp/chatwoot-backups"
LOG_FILE="/var/log/chatwoot-backup.log"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ── Helpers ───────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ── Localiza container do banco ───────────────────────────────
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'chatwoot.?db' | head -1)
if [[ -z "$DB_CONTAINER" ]]; then
  log "ERRO: container do PostgreSQL não encontrado"
  exit 1
fi
log "Usando container: $DB_CONTAINER"

mkdir -p "$BACKUP_DIR"

# ── Dump e upload de cada banco ───────────────────────────────
for DB in "${DATABASES[@]}"; do
  FILE="${DB}_${TIMESTAMP}.sql.gz"
  LOCAL_PATH="$BACKUP_DIR/$FILE"
  BLOB_NAME="$DB/$FILE"

  log "Iniciando dump: $DB"
  if docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB" | gzip > "$LOCAL_PATH"; then
    SIZE=$(du -sh "$LOCAL_PATH" | cut -f1)
    log "Dump concluído: $FILE ($SIZE)"
  else
    log "ERRO: falha no dump de $DB"
    exit 1
  fi

  log "Enviando para Azure Blob: $BLOB_NAME"
  az storage blob upload \
    --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
    --account-key "$AZURE_STORAGE_ACCESS_KEY" \
    --container-name "$BACKUP_CONTAINER" \
    --name "$BLOB_NAME" \
    --file "$LOCAL_PATH" \
    --overwrite \
    --output none

  log "Upload concluído: $BLOB_NAME"
  rm -f "$LOCAL_PATH"
done

# ── Remove backups antigos (> RETENTION_DAYS dias) ────────────
log "Removendo backups com mais de $RETENTION_DAYS dias..."
CUTOFF=$(date -u -d "-${RETENTION_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)

for DB in "${DATABASES[@]}"; do
  az storage blob list \
    --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
    --account-key "$AZURE_STORAGE_ACCESS_KEY" \
    --container-name "$BACKUP_CONTAINER" \
    --prefix "$DB/" \
    --query "[?properties.lastModified < '$CUTOFF'].name" \
    --output tsv | while read -r BLOB; do
      if [[ -n "$BLOB" ]]; then
        az storage blob delete \
          --account-name "$AZURE_STORAGE_ACCOUNT_NAME" \
          --account-key "$AZURE_STORAGE_ACCESS_KEY" \
          --container-name "$BACKUP_CONTAINER" \
          --name "$BLOB" \
          --output none
        log "Removido: $BLOB"
      fi
    done
done

log "Backup concluído com sucesso."
