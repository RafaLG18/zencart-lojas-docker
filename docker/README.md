# Arquivos dos containers

Tudo aqui vai **para dentro** dos containers. Você não roda nada desta pasta à mão: o `docker compose` faz o build da imagem web e monta o init do banco.

```
docker/
+-- web/                    contexto de build da imagem zencart-local (as 10 lojas)
|   +-- Dockerfile
|   +-- zc-configure.php    roda no BUILD: gera os configure.php
|   +-- zc-entrypoint.sh    roda em TODA SUBIDA de cada loja
|   +-- zc-admin.php        chamado pelo entrypoint (e à mão, para restaurar o admin)
|   +-- auth.conf           Basic Auth do Apache
|   +-- php.ini             limites do PHP
+-- db/
    +-- init/01-grupos.sh   roda UMA VEZ, na 1a subida do MariaDB
```

## Ciclo de vida

```
 BUILD (docker compose build / up --build)          uma vez por imagem
   Dockerfile
     +-- instala extensões PHP + mariadb-client
     +-- baixa Zen Cart do GitHub
     +-- guarda o SQL de instalação em /usr/local/share/zencart/sql
     +-- admin/ -> manage/
     +-- zc-configure.php gera os configure.php
     +-- apaga zc_install/

 1a SUBIDA DO BANCO (volume zencart_db_data vazio)    uma vez
   db/init/01-grupos.sh -> 10 bancos + 10 usuários

 CADA SUBIDA DE CADA LOJA (grupoN)
   zc-entrypoint.sh
     +-- espera o banco do grupo
     +-- banco já provisionado?  sim -> só sobe o Apache
     |                           não -> importa SQL, zc-admin.php,
     |                                  ajusta SSLPWSTATUSCHECK, grava marcador
     +-- apache2-foreground
```

---

## web/Dockerfile

Imagem única `zencart-local:<versão>`, usada pelos 10 serviços `grupoN`. Base: `php:8.2-apache` (Debian 13).

| Etapa | Por quê |
|---|---|
| Extensões `mysqli pdo_mysql gd zip intl bcmath opcache` + `mod_rewrite` | Exigidas pelo Zen Cart 2.1 |
| `mariadb-client` | O entrypoint importa o SQL com o cliente `mariadb` |
| Copia `mysql_zencart.sql` e `mysql_utf8.sql` para `/usr/local/share/zencart/sql/` | O SQL oficial fica fora do site, porque `zc_install/` é apagado |
| `mv admin manage` | O Zen Cart **bloqueia o painel** se a pasta se chamar `admin` |
| `php zc-configure.php` | Gera os dois `configure.php` |
| `rm -rf zc_install` | O Zen Cart **bloqueia o painel** se o instalador existir; também impede reinstalações pelo navegador |

**Build args:**

| Arg | Padrão | Observação |
|---|---|---|
| `ZC_VERSION` | `2.1.0` | Também lido do `.env`/ambiente pelo compose. Outra versão pode mudar o SQL e os templates; teste antes. |
| `ADMIN_DIR` | `manage` | Ao mudar, ajuste também `ADMIN_DIR` em `scripts/gerar-credenciais.sh` (só afeta o texto do `credenciais.txt`). |

Mudanças aqui só valem com `docker compose up -d --build`. Os arquivos de lojas já criadas ficam no volume de cada grupo, e alterações no código do Zen Cart só chegam a um grupo depois de `scripts/reset-grupo.sh`.

---

## web/zc-configure.php

**Quando roda:** só no build (`php /tmp/zc-configure.php /var/www/html manage`), e depois é apagado da imagem.

Lê os templates do próprio instalador (`zc_install/includes/catalog-configure-template.php` e `admin-configure-template.php`) e troca os placeholders `%%_NOME_%%`:

| Placeholder | Vira | Por quê |
|---|---|---|
| `CATALOG_HTTP(S)_SERVER`, `HTTP_SERVER_ADMIN` | `getenv('ZC_URL') ?: 'http://' . $_SERVER['HTTP_HOST']` | Links seguem o endereço digitado no navegador |
| `DB_DATABASE`, `DB_SERVER_USERNAME`, `DB_SERVER_PASSWORD` | `getenv('DB_DATABASE')` etc. | Mesmo arquivo serve os 10 grupos |
| `DB_SERVER` | `db` | Nome do serviço no compose |
| Demais (`DB_CHARSET`, `DIR_FS_CATALOG`...) | Valores fixos (`utf8mb4`, `/var/www/html/`...) | Iguais para todos |

Se sobrar algum `%%_` sem troca (por exemplo, numa versão nova do Zen Cart), o script **falha o build** em vez de gerar um arquivo quebrado.

---

## web/zc-entrypoint.sh

**Quando roda:** em toda subida de cada container `grupoN`, antes do Apache.

1. **Espera o banco:** tenta conectar com o usuário do grupo, 60 vezes a cada 2 s. Se esgotar: `[zencart] banco zc_grupoN indisponível` e o container sai (e o `restart` tenta de novo).
2. **Verifica o marcador** `zc_docker_provisioned` no banco do grupo:
   - **Existe:** não toca no banco. É o caso normal depois da 1ª subida.
   - **Não existe:** instala a loja:
     1. importa `mysql_zencart.sql` e `mysql_utf8.sql`;
     2. roda `zc-admin.php`;
     3. grava `SSLPWSTATUSCHECK` (`0:0`, ou `1:1` se `ZC_URL` começa com https). Sem isso, o 1º acesso ao admin para numa tela de "auto-configuration";
     4. cria a tabela `zc_docker_provisioned`, **por último**.
3. Passa o controle ao entrypoint padrão do PHP (`apache2-foreground`).

**Por que o marcador é uma tabela própria:** se a importação for interrompida, o marcador não existe e a próxima subida refaz tudo (os SQLs têm `DROP TABLE IF EXISTS`). E, como não depende de dados que o grupo edita (como o nome do admin), mudar algo no painel nunca dispara uma reinstalação.

Usa `--skip-ssl`: o cliente MariaDB 11.8 do Debian 13 exige SSL por padrão, e o tráfego fica na rede interna `backend`.

**Logs esperados** (`docker compose logs grupoN`):

```
[zencart] instalando loja em zc_grupoN      <- só na 1a subida ou após reset
[zencart] admin 'grupoN' configurado
```

---

## web/zc-admin.php

Define o admin (`admin_id = 1`) com os dados do ambiente:

- usuário `ADMIN_USER`, senha `ADMIN_PASSWORD` (hash `password_hash`, o mesmo do Zen Cart);
- e-mail `<usuário>@localhost`;
- `pwd_last_change_date = NOW()`, para o painel não forçar a troca de senha no 1º login.

Chamado pelo entrypoint só na instalação, para não desfazer uma senha trocada pelo grupo no painel. Também serve para **restaurar a senha do admin** sem apagar dados:

```bash
docker compose exec grupoN php /usr/local/bin/zc-admin.php
```

---

## web/auth.conf e web/php.ini

- **auth.conf:** exige Basic Auth em todo `/var/www/html` (loja e `/manage`). O arquivo de senhas `/etc/apache2/.htpasswd` é montado pelo compose a partir de `auth/grupoN.htpasswd`, um por grupo.
- **php.ini:** `memory_limit 256M`, uploads até 32 MB, `max_execution_time 120`, fuso `America/Recife`.

---

## db/init/01-grupos.sh

**Quando roda:** só quando o MariaDB sobe com o volume `zencart_db_data` **vazio** (mecanismo `docker-entrypoint-initdb.d` da imagem oficial). Em subidas seguintes, é ignorado.

Para cada N de 1 a 10:

```sql
CREATE DATABASE zc_grupoN CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'grupoN'@'%' IDENTIFIED BY '<GRUPON_DB_PASSWORD>';
GRANT ALL PRIVILEGES ON zc_grupoN.* TO 'grupoN'@'%';
```

O usuário de cada grupo só enxerga o próprio banco: tentar `USE zc_grupo2` como `grupo1` dá `Access denied`. O script **não instala a loja**; isso é feito pelo entrypoint de cada `grupoN`.

Para que ele rode de novo (por exemplo, depois de trocar as senhas), é preciso apagar o volume do banco: `docker compose down -v`, o que **apaga todas as lojas**.

---

## Variáveis de ambiente

Definidas no `docker-compose.yml`, com valores vindos do `.env` gerado por `scripts/gerar-credenciais.sh`.

**Serviço `db`:**

| Variável | Uso |
|---|---|
| `MARIADB_ROOT_PASSWORD` | Senha de root (imagem oficial); usada pelo init e pelo `reset-grupo.sh` |
| `GRUPO1_DB_PASSWORD` … `GRUPO10_DB_PASSWORD` | Senhas dos usuários criados pelo `01-grupos.sh` |

**Serviços `grupo1` … `grupo10`:**

| Variável | Exemplo | Uso |
|---|---|---|
| `DB_DATABASE` | `zc_grupo3` | Banco do grupo (`configure.php`, entrypoint) |
| `DB_USER` | `grupo3` | Usuário do banco |
| `DB_PASSWORD` | `GRUPO3_DB_PASSWORD` | Senha do banco |
| `ADMIN_USER` | `grupo3` | Usuário do admin, aplicado na instalação |
| `ADMIN_PASSWORD` | `GRUPO3_ADMIN_PASSWORD` | Senha do admin, aplicada na instalação |
| `ZC_URL` | vazio | Endereço fixo da loja; vazio = endereço do navegador |
