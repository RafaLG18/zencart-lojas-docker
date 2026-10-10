## 1. Preparação

- [x] 1.1 Fazer backup do diretório atual (`tar czf ../zencart-backup-<data>.tgz .`) e verificar que o arquivo foi criado
- [x] 1.2 Derrubar o layout antigo, se houver algo de pé (`docker compose -p grupoN --env-file envs/grupoN.env down -v` para N=1..10), e verificar que `docker ps -a` e `docker volume ls` não listam containers ou volumes `grupoN`

## 2. Imagem web pré-instalada

- [x] 2.1 No `docker/web/Dockerfile`, instalar `mariadb-client` e copiar `zc_install/sql/install/*.sql` para `/usr/local/share/zencart/sql/`; verificar com `docker run --rm --entrypoint ls zencart-local:2.1.0 /usr/local/share/zencart/sql`
- [x] 2.2 Gerar `includes/configure.php` e o configure do admin a partir dos templates do instalador, com valores fixos e `getenv()` (DB_DATABASE, DB_SERVER_USERNAME, DB_SERVER_PASSWORD, HTTP(S)_SERVER via `ZC_URL` ou `HTTP_HOST`); verificar com `php -l` nos dois arquivos dentro da imagem e com `grep -c %%_` retornando 0
- [x] 2.3 Renomear `admin` para `manage` e remover `zc_install` no build; verificar que `/var/www/html/manage/includes/configure.php` existe e `/var/www/html/zc_install` e `/var/www/html/admin` não existem na imagem
- [x] 2.4 Reescrever `docker/web/zc-entrypoint.sh`: aguardar o banco com o usuário do grupo (retry 60 × 2 s), checar a tabela marcadora `zc_docker_provisioned`, importar `mysql_zencart.sql` + `mysql_utf8.sql` se faltar, aplicar o admin via `docker/web/zc-admin.php` e, por último, criar o marcador; verificar com `bash -n` e pelo teste 5.2
- [x] 2.5 Ajustar `docker/web/zc-admin.php` para ler o banco e o usuário do ambiente (`DB_DATABASE`, `DB_USER`) e gravar `admin_email = <grupo>@localhost`; verificar com `php -l`

## 3. Banco compartilhado com isolamento

- [x] 3.1 Criar `docker/db/init/01-grupos.sh` (montado em `/docker-entrypoint-initdb.d`) que cria `zc_grupoN` (utf8mb4), o usuário `grupoN` com a senha `GRUPON_DB_PASSWORD` e `GRANT ALL ON zc_grupoN.*` para N=1..10; verificar com `bash -n` e pelo teste 5.3

## 4. Compose, credenciais e reset

- [x] 4.1 Reescrever `docker-compose.yml`: serviço `db` (mariadb:10.11, só rede `backend` interna, healthcheck, `docker/db/init/` montado, senhas dos grupos no ambiente) e `grupo1`..`grupo10` via âncora `x-web` (portas 8012..8021, `DB_DATABASE`/`DB_USER`/`DB_PASSWORD`/`ADMIN_USER`/`ADMIN_PASSWORD`/`ZC_URL`, volume `grupoN_files`, `auth/grupoN.htpasswd`), com uma única build da imagem; verificar com `docker compose config -q`
- [x] 4.2 Usar `${VAR:?rode ./scripts/gerar-credenciais.sh}` nas variáveis obrigatórias; verificar que `docker compose config` sem `.env` falha com essa mensagem
- [x] 4.3 Criar `scripts/gerar-credenciais.sh`: aborta se `.env` existir; gera `.env` (600), `auth/grupoN.htpasswd` (apr1) e `credenciais.txt` (600) com URL, Basic Auth e admin por grupo, sem senhas de root ou de banco; aceita `HOST` opcional para as URLs; verificar que uma segunda execução não altera o `sha256sum` de `.env`
- [x] 4.4 Criar `scripts/reset-grupo.sh N [-y]`: valida N em 1..10, pede confirmação digitando `grupoN`, remove o container e o volume `grupoN_files`, faz DROP/CREATE de `zc_grupoN` como root e sobe `grupoN`; verificar com `bash -n`, com `./scripts/reset-grupo.sh 11` falhando sem efeitos e pelo teste 5.5
- [x] 4.5 Remover `grupos.sh`, `exportar-modelo.sh`, `seed/`, `envs/`, os `auth/*.htpasswd` antigos e o `credenciais.txt` antigo; verificar com `ls`

## 5. Validação de ponta a ponta

- [x] 5.1 `./scripts/gerar-credenciais.sh && docker compose up -d --build`; verificar que `docker compose ps` mostra 11 containers em execução (db healthy)
- [x] 5.2 Para N=1..10: `curl -o /dev/null -w '%{http_code}' http://localhost:$((8011+N))/` retorna 401; com `-u grupoN:<senha>` retorna 200 e o HTML não contém `zc_install`; `/admin` e `/zc_install` autenticados retornam 404
- [x] 5.3 Isolamento: `docker compose exec db mariadb -ugrupo1 -p<senha> -e 'USE zc_grupo2'` falha com access denied; `docker compose port db 3306` não publica porta
- [x] 5.4 No navegador, logar em `/manage` do grupo1 com o admin do `credenciais.txt` sem ser forçado a trocar a senha; confirmar catálogo sem produtos; trocar a senha, `docker compose restart grupo1` e confirmar que a nova senha vale
- [x] 5.5 Cadastrar um produto no grupo4 e no grupo5, rodar `./scripts/reset-grupo.sh 4 -y`; verificar que o grupo4 volta sem produtos e aceita as mesmas credenciais, e que o produto do grupo5 continua lá
- [x] 5.6 `docker compose down && docker compose up -d`; verificar que os dados do grupo5 persistem e nenhuma loja é reinstalada (logs do entrypoint sem importação)
