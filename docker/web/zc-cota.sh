#!/bin/bash
# Cota suave de disco: mede a pasta da loja periodicamente e, acima da cota,
# desliga o envio de arquivos pelo PHP até o uso voltar para baixo dela.
set -u
ROOT=/var/www/html
STATE=/run/zc/cota.uso
BLOCK_INI=/usr/local/etc/php/conf.d/zz-cota.ini
QUOTA_MB=${DISK_QUOTA_MB:-2048}
INTERVAL=${QUOTA_CHECK_SECONDS:-300}

mkdir -p "$(dirname "$STATE")"
while true; do
  used=$(du -sb "$ROOT" 2>/dev/null | cut -f1)
  echo "${used:-0}" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

  if [ "${used:-0}" -gt $((QUOTA_MB * 1024 * 1024)) ]; then
    if [ ! -e "$BLOCK_INI" ]; then
      echo "file_uploads = Off" > "$BLOCK_INI"
      apachectl graceful
      echo "[zencart] cota de $QUOTA_MB MB excedida: envio de arquivos bloqueado"
    fi
  elif [ -e "$BLOCK_INI" ]; then
    rm -f "$BLOCK_INI"
    apachectl graceful
    echo "[zencart] uso abaixo da cota: envio de arquivos liberado"
  fi

  sleep "$INTERVAL"
done
