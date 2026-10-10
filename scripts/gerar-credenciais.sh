#!/usr/bin/env bash
# Gera, uma única vez, as senhas dos 10 grupos para o docker compose.
# Uso: [HOST=ip-ou-nome] ./scripts/gerar-credenciais.sh
#   HOST opcional: fixa a URL das lojas; vazio = usa o endereço do navegador
#   (as URLs do credenciais.txt usam o IP detectado desta máquina)
set -euo pipefail
cd "$(dirname "$0")/.."

N=10
BASE_PORT=8011   # grupo1 = 8012
ADMIN_DIR=manage
HOST=${HOST:-}

# IP desta máquina na rede local; só aparece no credenciais.txt, não fixa nada nas lojas
detect_ip() {
  local a=""
  if command -v ip >/dev/null; then
    a=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}') || true
  fi
  if [ -z "$a" ] && [ "$(uname)" = Darwin ]; then
    a=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null) || true
  fi
  if [ -z "$a" ]; then
    a=$(hostname -I 2>/dev/null | awk '{print $1}') || true
  fi
  [[ "$a" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && echo "$a" || echo "<ip-do-servidor>"
}
SHOW_HOST=${HOST:-$(detect_ip)}

if [ -e .env ]; then
  echo ".env já existe; nada foi alterado. Apague .env, auth/ e credenciais.txt para gerar de novo." >&2
  exit 1
fi

umask 077
mkdir -p auth
rand() { openssl rand -hex "$1"; }

{
  echo "DB_ROOT_PASSWORD=$(rand 16)"
} > .env
: > credenciais.txt

for i in $(seq 1 "$N"); do
  g="grupo$i"
  port=$((BASE_PORT + i))
  url="http://$SHOW_HOST:$port"
  web_pass=$(rand 6)
  admin_pass="$(rand 6)Zc1"

  {
    echo "GRUPO${i}_DB_PASSWORD=$(rand 16)"
    echo "GRUPO${i}_ADMIN_PASSWORD=$admin_pass"
    [ -n "$HOST" ] && echo "GRUPO${i}_URL=http://$HOST:$port"
  } >> .env

  printf '%s:%s\n' "$g" "$(openssl passwd -apr1 "$web_pass")" > "auth/$g.htpasswd"
  chmod 644 "auth/$g.htpasswd"   # lido pelo Apache (www-data) dentro do container

  cat >> credenciais.txt <<CRED
[$g]
loja=$url
usuario=$g
senha=$web_pass
admin=$url/$ADMIN_DIR
admin_usuario=$g
admin_senha=$admin_pass

CRED
done

echo "Gerados .env, auth/*.htpasswd e credenciais.txt para $N grupos."
echo "URLs em credenciais.txt usam: $SHOW_HOST"
echo "Próximo passo: docker compose up -d --build"
