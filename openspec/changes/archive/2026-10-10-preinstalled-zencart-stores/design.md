## Context

Hoje há um projeto Compose por grupo (`grupos.sh` faz `docker compose -p grupoN`), cada um com seu MariaDB, e a instalação depende de um grupo modelo exportado para `seed/`. Ver proposal.md (Why).

Fatos do Zen Cart 2.1.0 que moldam a abordagem:

- `zc_install/sql/install/mysql_zencart.sql` + `mysql_utf8.sql` importam limpos direto pelo cliente `mariadb` (spike: 108 tabelas, `project_version` 2.1.0, zero erros). O parser do instalador (`zcDatabaseInstaller::parseSqlFile`) não é necessário com prefixo vazio.
- O modo CLI do instalador (`zc_install/includes/cli_controller.php`) está incompleto na 2.1.0 (lê `$_POST`, não carrega o SQL principal). Não é usável.
- `admin/includes/init_includes/init_admin_auth.php` redireciona para a página de alerta se `DIR_WS_ADMIN` termina em `/admin/` ou se `zc_install` existe. Logo, renomear o admin e remover o instalador são obrigatórios.
- O instalador apenas faz `UPDATE admin ... WHERE admin_id = 1` para definir o admin; o SQL base já insere esse registro.
- Os templates `zc_install/includes/{catalog,admin}-configure-template.php` usam placeholders `%%_NOME_%%`.

## Goals / Non-Goals

**Goals:**
- Uma única definição Compose, reproduzível do zero, sem artefatos gerados a partir de uma instalação manual.
- Toda lógica de "instalar uma loja" em um só lugar, usada tanto na primeira subida quanto no reset.

**Non-Goals:**
- Número de grupos variável em tempo de execução (fixo em 10; mudar exige editar o Compose).
- HTTPS / proxy reverso.
- Migrar dados dos volumes do layout antigo (`-p grupoN`).
- Backup automático dos bancos.
- Tradução pt-BR, moeda ou qualquer personalização além da instalação padrão.

## Decisions

### 1. Topologia: 1 MariaDB + 10 serviços web em um único Compose

Serviços `db` e `grupo1`..`grupo10`. Os 10 serviços web compartilham um bloco YAML via âncora (`x-web: &web`) e diferem só em porta, variáveis do grupo, volume de arquivos e arquivo htpasswd. `db` fica apenas na rede `backend` (`internal: true`), sem `ports`.

- *Alternativa:* manter 10 projetos com 10 MariaDBs (B). Rejeitada: o dobro de containers e de RAM, e exige script de loop em vez de `docker compose up`.

### 2. O banco só cria bancos e usuários; quem instala a loja é o container web

- **db (initdb, 1ª subida):** um `.sh` em `/docker-entrypoint-initdb.d` faz, para N=1..10, `CREATE DATABASE zc_grupoN` (utf8mb4), `CREATE USER 'grupoN'@'%'` com a senha do `.env` e `GRANT ALL ON zc_grupoN.*`. As senhas chegam ao container `db` por variáveis de ambiente.
- **web (entrypoint, toda subida):** conecta com o usuário do grupo (com retry) e verifica se a tabela `configuration` existe. Se não existir, importa `mysql_zencart.sql` + `mysql_utf8.sql` e define o admin (usuário `grupoN`, senha do `.env`, `pwd_last_change_date = NOW()` para não forçar troca). Se existir, não toca no banco.

Os SQLs ficam na imagem web fora do docroot (ex.: `/usr/local/share/zencart/sql`), copiados de `zc_install` antes de removê-lo. A imagem ganha o pacote `mariadb-client`.

Por que no web e não no db:
- O reset fica trivial: esvaziar `zc_grupoN` e recriar o container/volume; o web reinstala sozinho na subida.
- Os SQLs já estão no tarball que a imagem web baixa; o db continua sendo a imagem oficial, sem build próprio.
- O usuário do grupo tem `GRANT ALL` no próprio banco, suficiente para importar o schema.
- Aplicar o admin só quando o banco está vazio preserva a senha que o grupo trocar pelo painel.

- *Alternativa:* `provisionar-grupo.sh` dentro do `db` (desenho discutido inicialmente). Rejeitada: exigiria imagem MariaDB customizada só para carregar os SQLs e duplicaria a lógica de admin.
- *Alternativa:* usar o `cli_controller.php` do Zen Cart. Rejeitada: incompleto na 2.1.0.

### 3. Imagem web única, já "instalada" no build

No `docker/web/Dockerfile`, após baixar o Zen Cart:
1. Copiar `zc_install/sql/install/*.sql` para `/usr/local/share/zencart/sql/`.
2. Gerar `includes/configure.php` e `manage/includes/configure.php` a partir dos templates do instalador, substituindo os placeholders por valores fixos (`DIR_FS_CATALOG=/var/www/html/`, `DB_SERVER=db`, charset `utf8mb4`, prefixo vazio, cache `none`) e por `getenv()` onde varia por grupo: `DB_DATABASE`, `DB_SERVER_USERNAME`, `DB_SERVER_PASSWORD` e `HTTP(S)_SERVER = getenv('ZC_URL') ?: 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost')`.
3. `mv admin manage` e `rm -rf zc_install`.

Uma só imagem (`zencart-local:2.1.0`) serve os 10 grupos; o que muda vem do ambiente. Isso substitui o `seed/web` e o `exportar-modelo.sh`.

- *Alternativa:* gerar o `configure.php` no entrypoint a cada subida. Rejeitada: com `getenv()` o arquivo é o mesmo para todos e pode nascer no build.

### 4. Arquivos de cada loja em volume próprio

Cada `grupoN` monta um volume nomeado `grupoN_files` em `/var/www/html`, populado pela imagem na primeira criação. Ele guarda imagens de produtos enviadas e plugins instalados pelo grupo.

Consequência: atualizar a imagem não altera lojas já criadas. Para isso é preciso o reset.

### 5. Credenciais: `scripts/gerar-credenciais.sh` → `.env` + `auth/` + `credenciais.txt`

O script aborta, sem alterar nada, se `.env` já existir. Caso contrário gera:
- `.env` (modo 600): `DB_ROOT_PASSWORD` e, por grupo, `GRUPON_DB_PASSWORD`, `GRUPON_ADMIN_PASSWORD`. Opcional `ZC_URL_BASE`/`HOST` se informado ao script.
- `auth/grupoN.htpasswd` (apr1) com usuário `grupoN` e a senha de Basic Auth; a senha em texto puro só vai para o `credenciais.txt`.
- `credenciais.txt` (modo 600): por grupo, URL da loja, Basic Auth, URL `/manage` e admin. Sem senha de root nem de banco.

No Compose, as variáveis usam `${VAR:?rode ./scripts/gerar-credenciais.sh}` para falhar com mensagem clara se o `.env` não existir.

O usuário de admin é `grupoN`; o e-mail do admin fica `grupoN@localhost`.

- *Alternativa:* entregar também as senhas de banco aos grupos (como hoje). Rejeitada: sem instalador, os grupos não precisam delas e o banco nem é alcançável de fora.

### 6. Reset: `scripts/reset-grupo.sh N`

1. Valida `N` em 1..10 e pede confirmação digitando o nome do grupo (`-y` pula).
2. `docker compose stop grupoN && docker compose rm -f grupoN`.
3. `docker volume rm <projeto>_grupoN_files`.
4. `DROP DATABASE zc_grupoN; CREATE DATABASE zc_grupoN ...` via `docker compose exec db` como root. Os grants em nível de banco sobrevivem ao DROP/CREATE, então o usuário continua com acesso.
5. `docker compose up -d grupoN`. O entrypoint vê o banco vazio e reinstala.

As credenciais não mudam, porque vêm do `.env` e do htpasswd.

### 7. Portas fixas no Compose

`grupoN` publica `8011+N:80` escrito literalmente (Compose não faz aritmética). Mantém as URLs atuais (8012..8021).

### 8. Organização da pasta

`docker-compose.yml` fica na raiz (para `docker compose up` funcionar dali). Tudo que vai para os containers fica em `docker/` (`docker/web/` é o contexto de build da imagem; `docker/db/init/` é montado no initdb do MariaDB), e os comandos de operação ficam em `scripts/`. Com o contexto de build restrito a `docker/web/`, `.env`, `auth/` e `credenciais.txt` não são enviados ao build.

## Risks / Trade-offs

- [MariaDB único é ponto único de falha] → `restart: unless-stopped` + healthcheck; aceitável para ambiente de aula.
- [O web sobe antes do initdb terminar de criar os usuários; o `healthcheck.sh --connect` pode passar via socket durante a inicialização] → o entrypoint do web tenta conectar com o próprio usuário em loop (ex.: 60 × 2 s) antes de decidir instalar.
- [Duas subidas simultâneas importando o mesmo banco] → cada banco tem um único container web; o reset para o container antes de esvaziar o banco.
- [Importação interrompida deixa o banco pela metade e a próxima subida vê `configuration` e não reinstala] → o entrypoint importa, aplica o admin e só por último cria a tabela marcadora `zc_docker_provisioned`; a verificação usa essa tabela em vez de só a existência de `configuration`. Se o marcador faltar, ele recria o schema (os SQLs fazem `DROP TABLE IF EXISTS`). O marcador não depende de dados editáveis pelo grupo (ex.: `admin_name`), para que renomear o admin pelo painel não dispare uma reinstalação.
- [Imagem base `php:8.2-apache` em Debian 13 traz cliente MariaDB 11.8, que exige SSL por padrão] → o entrypoint usa `--skip-ssl`; o tráfego fica na rede `backend` interna.
- [Compose reconstrói a mesma imagem para cada um dos 10 serviços] → `build` só no `grupo1` com `image: zencart-local:2.1.0`, e os demais apenas com `image` + `pull_policy: never`; ou uma âncora com `build` aproveitando o cache de camadas. Escolher na implementação, o que não muda o comportamento.
- [Volume de arquivos não recebe atualizações da imagem] → documentado; o reset recria.
- [`credenciais.txt` em texto puro] → arquivo com modo 600; responsabilidade do professor distribuir.

## Migration Plan

1. Derrubar o layout antigo: para cada grupo, `docker compose -p grupoN --env-file envs/grupoN.env down -v` (não há dados a preservar; nada estava em uso).
2. Remover `grupos.sh`, `exportar-modelo.sh`, `seed/`, `envs/`, `auth/*.htpasswd` e `credenciais.txt` antigos.
3. `./scripts/gerar-credenciais.sh` → `docker compose up -d --build`.
4. Validar: 10 lojas respondem 401 sem credencial, 200 com credencial, `/manage` aceita o admin do grupo.

Rollback: os arquivos antigos podem ser recuperados de um backup feito antes do passo 2 (o diretório não é repositório git).
