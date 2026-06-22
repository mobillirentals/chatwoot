#!/bin/bash
# Emite o certificado SSL Let's Encrypt para o domínio do Chatwoot.
# Execute na VM APÓS o registro DNS ter propagado:
#   ssh chatwoot@<IP>
#   sudo /opt/chatwoot/scripts/certbot-init.sh
#
# Pré-requisito: porta 80 acessível publicamente (Nginx deve estar parado).

set -euo pipefail

DOMAIN="${DOMAIN:-chat.mobillirentals.com.br}"
EMAIL="${LETSENCRYPT_EMAIL:-ti@mobillirentals.com.br}"

echo "==> Parando Nginx para liberar a porta 80..."
docker compose -f /opt/chatwoot/docker-compose.production.yaml stop nginx 2>/dev/null || true

echo "==> Emitindo certificado para $DOMAIN..."
certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN"

echo "==> Reiniciando Nginx com SSL..."
docker compose -f /opt/chatwoot/docker-compose.production.yaml start nginx

echo ""
echo "✅ Certificado emitido com sucesso!"
echo "   Caminho: /etc/letsencrypt/live/$DOMAIN/"
echo ""
echo "   Renovação automática já configurada via cron (/etc/cron.d/certbot-renew)."
