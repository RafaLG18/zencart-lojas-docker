#!/bin/bash
# Instala a loja no banco do grupo quando ele ainda não foi provisionado
# (primeira subida ou após reset-grupo.sh). Depois disso, não toca no banco.
set -euo pipefail
SQL_DIR=/usr/local/share/zencart/sql
export MYSQL_PWD="$DB_PASSWORD"
db() { mariadb --skip-ssl -h db -u "$DB_USER" "$DB_DATABASE" "$@"; }

for i in $(seq 1 60); do
  db -e 'SELECT 1' >/dev/null 2>&1 && break
  [ "$i" -eq 60 ] && { echo "[zencart] banco $DB_DATABASE indisponível" >&2; exit 1; }
  sleep 2
done

if ! db -e 'SELECT 1 FROM zc_docker_provisioned' >/dev/null 2>&1; then
  echo "[zencart] instalando loja em $DB_DATABASE"
  db --default-character-set=utf8mb4 < "$SQL_DIR/mysql_zencart.sql"
  db --default-character-set=utf8mb4 < "$SQL_DIR/mysql_utf8.sql"
  php /usr/local/bin/zc-admin.php
  # O instalador oficial preenche isto; vazio, o 1º acesso ao admin para numa auto-configuração
  ssl=0; [[ "${ZC_URL:-}" == https* ]] && ssl=1
  db -e "UPDATE configuration SET configuration_value = '$ssl:$ssl' WHERE configuration_key = 'SSLPWSTATUSCHECK'"
  # Marcador gravado por último: importação interrompida é refeita na próxima subida
  db -e 'CREATE TABLE zc_docker_provisioned (provisioned_at DATETIME NOT NULL); INSERT INTO zc_docker_provisioned VALUES (NOW())'
fi

exec docker-php-entrypoint "$@"
