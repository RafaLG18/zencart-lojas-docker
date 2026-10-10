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
  # Arquivos graváveis pelo grupo www-data, ao qual o usuário SSH do grupo pertence
  chgrp -R www-data /var/www/html
  chmod -R g+w /var/www/html
  find /var/www/html -type d -exec chmod g+s {} +
  # A imagem base deixa a raiz em 1777; o sticky bit impediria o grupo de apagar arquivos do Apache
  chmod 2775 /var/www/html
fi

# Acesso SSH do grupo. O usuário é recriado a cada container novo (sistema de arquivos efêmero);
# o login do grupo é o mesmo do banco (grupoN)
GRUPO=$DB_USER
mkdir -p /etc/zc
printf 'GRUPO=%s\nDB_DATABASE=%s\nDISK_QUOTA_MB=%s\n' "$GRUPO" "$DB_DATABASE" "${DISK_QUOTA_MB:-2048}" > /etc/zc/limites.conf
id "$GRUPO" >/dev/null 2>&1 || useradd -m -d "/home/$GRUPO" -s /bin/bash -G www-data "$GRUPO"
echo "$GRUPO:$SSH_PASSWORD" | chpasswd
ln -sfn /var/www/html "/home/$GRUPO/loja"
printf '[client]\nhost=db\nuser=%s\npassword=%s\ndatabase=%s\nskip-ssl\n' "$DB_USER" "$DB_PASSWORD" "$DB_DATABASE" > "/home/$GRUPO/.my.cnf"
chown "$GRUPO:$GRUPO" "/home/$GRUPO/.my.cnf"
chmod 600 "/home/$GRUPO/.my.cnf"

# Chave de host montada de ssh/ no host: o sshd exige dono root e modo 600
install -m 600 /run/zc-ssh-host/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
install -m 644 /run/zc-ssh-host/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
echo "AllowUsers $GRUPO" > /etc/ssh/sshd_config.d/zc-grupo.conf
mkdir -p /run/sshd
/usr/sbin/sshd

/usr/local/bin/zc-cota.sh &

exec docker-php-entrypoint "$@"
