# Scripts de operação

Comandos rodados **no host**, a partir de qualquer pasta (cada script vai sozinho para a raiz do projeto). Precisam de `bash`, `openssl` e Docker com Compose.

| Script | Quando usar |
|---|---|
| [`gerar-credenciais.sh`](gerar-credenciais.sh) | Uma vez, antes da primeira subida (ou em um computador novo) |
| [`reset-grupo.sh`](reset-grupo.sh) | Quando um grupo precisa recomeçar a loja do zero |

---

## gerar-credenciais.sh

Gera todas as senhas do ambiente, de uma vez, para os 10 grupos.

```bash
./scripts/gerar-credenciais.sh
HOST=192.168.0.10 ./scripts/gerar-credenciais.sh   # opcional, ver "Variável HOST"
```

### O que cria

| Arquivo | Permissão | Conteúdo | Quem usa |
|---|---|---|---|
| `.env` | 600 | `DB_ROOT_PASSWORD`, `GRUPON_DB_PASSWORD`, `GRUPON_ADMIN_PASSWORD` (e `GRUPON_URL` se `HOST` foi usado) | `docker compose` |
| `auth/grupoN.htpasswd` | 644 | Usuário `grupoN` + hash apr1 da senha do navegador | Apache de cada loja (Basic Auth) |
| `credenciais.txt` | 600 | Por grupo: URL da loja, usuário/senha do navegador, URL do `/manage`, usuário/senha do admin | Você, para entregar aos grupos |

Senhas geradas com `openssl rand`:

| Senha | Formato | Onde aparece |
|---|---|---|
| Root do MariaDB | 32 hex | Só no `.env` |
| Banco de cada grupo | 32 hex | Só no `.env` (os grupos não precisam dela) |
| Navegador (Basic Auth) | 12 hex | `credenciais.txt` em texto puro; `auth/` só com hash |
| Admin do Zen Cart | 12 hex + `Zc1` | `.env` e `credenciais.txt` |

### Regras

- **Nunca sobrescreve.** Se `.env` já existir, avisa, sai com código 1 e não altera nada.
- **Para gerar senhas novas**, apague `.env`, `auth/` e `credenciais.txt`, rode o script e depois `docker compose down -v && docker compose up -d`. O `-v` é obrigatório: os usuários do banco foram criados com as senhas antigas, e isso **apaga os dados de todas as lojas**.

### IP nas URLs do credenciais.txt

Sem `HOST`, o script detecta o IP desta máquina na rede local e o usa **só no texto** do `credenciais.txt`. A detecção tenta, nesta ordem:

1. `ip route get 1.1.1.1` (Linux)
2. `ipconfig getifaddr en0` / `en1` (macOS)
3. `hostname -I`

Se nenhuma devolver um IPv4, as URLs saem como `<ip-do-servidor>`. A última linha da saída mostra o que foi usado:

```
URLs em credenciais.txt usam: 192.168.1.16
```

### Variável HOST

`HOST=<ip-ou-nome>` faz duas coisas: usa esse endereço no `credenciais.txt` e grava `GRUPON_URL=http://<HOST>:<porta>` no `.env`. Com isso, as lojas passam a gerar links sempre com esse endereço, ignorando o que foi digitado no navegador.

Use só se precisar forçar um nome. Sem `HOST`, o projeto funciona em qualquer máquina e rede.

---

## reset-grupo.sh

Devolve **uma** loja ao estado recém-instalado: apaga o banco e os arquivos daquele grupo e reinstala a loja do zero.

```bash
./scripts/reset-grupo.sh 3        # pede para digitar "grupo3" como confirmação
./scripts/reset-grupo.sh 3 -y     # sem confirmação (para automação)
```

### O que faz, em ordem

1. Valida o número (1 a 10). Fora disso, mostra o uso e sai com código 1.
2. Pede confirmação, a menos que receba `-y`. Resposta errada: `Cancelado; nada foi apagado.`
3. `docker compose rm -sf grupoN`: para e remove o container.
4. `docker volume rm zencart_grupoN_files`: apaga os arquivos da loja (imagens enviadas, plugins).
5. Como root, no container `db`: `DROP DATABASE zc_grupoN` + `CREATE DATABASE zc_grupoN`.
6. `docker compose up -d grupoN`: o container sobe, vê o banco vazio e reinstala a loja (ver [docker/README.md](../docker/README.md#webzc-entrypointsh)).

### O que é mantido

- **Todas as senhas.** O usuário de banco e seu GRANT sobrevivem ao DROP/CREATE, e o `.htpasswd` e o `.env` não mudam. O `credenciais.txt` já entregue continua valendo.
- **Os outros 9 grupos**, que não são parados nem tocados.

A reinstalação leva poucos segundos. Para acompanhar:

```bash
docker compose logs -f grupo3     # espere: [zencart] admin 'grupo3' configurado
```

---

## Comandos manuais úteis

| Situação | Comando |
|---|---|
| Grupo esqueceu a senha do admin (volta à do `credenciais.txt`, sem apagar dados) | `docker compose exec grupoN php /usr/local/bin/zc-admin.php` |
| Abrir o banco de um grupo como o próprio grupo | `docker compose exec db mariadb -ugrupoN -p zc_grupoN` (senha: `GRUPON_DB_PASSWORD` do `.env`) |
| Abrir o MariaDB como root | `docker compose exec db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"'` |
| Atualizar o IP no `credenciais.txt` sem trocar senhas | `sed -i 's/<ip-antigo>/<ip-novo>/' credenciais.txt` |
