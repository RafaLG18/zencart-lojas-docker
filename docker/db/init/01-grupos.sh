#!/bin/bash
# Roda uma única vez, no primeiro start do MariaDB: cria um banco e um usuário
# por grupo, com acesso apenas ao próprio banco. A loja é instalada pelo web.
set -euo pipefail

for i in $(seq 1 10); do
  var="GRUPO${i}_DB_PASSWORD"
  pass="${!var:?senha do grupo$i ausente; rode ./scripts/gerar-credenciais.sh}"
  mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" <<SQL
CREATE DATABASE IF NOT EXISTS zc_grupo$i CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'grupo$i'@'%' IDENTIFIED BY '$pass';
GRANT ALL PRIVILEGES ON zc_grupo$i.* TO 'grupo$i'@'%';
SQL
  echo "[db-init] zc_grupo$i e usuário grupo$i criados"
done
