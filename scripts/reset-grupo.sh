#!/usr/bin/env bash
# Devolve a loja de um grupo ao estado recém-instalado (banco e arquivos),
# mantendo as mesmas credenciais. Os demais grupos não são afetados.
# Uso: ./scripts/reset-grupo.sh N [-y]
set -euo pipefail
cd "$(dirname "$0")/.."

N=${1:-}
if ! [[ "$N" =~ ^([1-9]|10)$ ]]; then
  echo "Uso: $0 N [-y]   (N de 1 a 10)" >&2
  exit 1
fi
g="grupo$N"

if [ "${2:-}" != "-y" ]; then
  echo "ATENÇÃO: todos os dados e arquivos da loja do $g serão apagados."
  read -r -p "Digite '$g' para confirmar: " resp
  [ "$resp" = "$g" ] || { echo "Cancelado; nada foi apagado."; exit 1; }
fi

docker compose rm -sf "$g"
docker volume rm "zencart_${g}_files"
docker compose exec -T db sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -e \
  'DROP DATABASE IF EXISTS zc_$g; CREATE DATABASE zc_$g CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'"
docker compose up -d "$g"

echo "$g resetado; a loja é reinstalada na subida (acompanhe: docker compose logs -f $g)."
