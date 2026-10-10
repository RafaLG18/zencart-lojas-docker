## Why

Hoje, subir as 10 lojas Zen Cart exige instalar o grupo1 à mão no navegador, exportá-lo como modelo (`exportar-modelo.sh`), resetar os grupos 2..10 e subir tudo de novo. São quatro etapas manuais, fáceis de errar na ordem e sem nenhuma personalização real além da instalação básica. O próprio Zen Cart 2.1.0 traz os SQLs de instalação em formato importável direto pelo MariaDB (validado: 108 tabelas, versão 2.1.0, sem erros), então a instalação pode ser 100% automática.

## What Changes

- Um único `docker-compose.yml` sobe **1 MariaDB + 10 serviços web** já instalados com `docker compose up -d`, sem passar pelo instalador.
- Cada grupo tem **banco próprio (`zc_grupoN`) e usuário próprio (`grupoN`)** com permissão apenas no seu banco, dentro do mesmo MariaDB.
- A imagem web é construída já pronta: `zc_install` removido, pasta do admin renomeada para **`/manage`**, `configure.php` lendo banco/usuário/senha/URL de variáveis de ambiente.
- O MariaDB cria os 10 bancos e usuários no primeiro start; cada loja instala o próprio banco na primeira subida a partir dos SQLs oficiais (`mysql_zencart.sql` + `mysql_utf8.sql`), **sem dados de demonstração**.
- Novo `scripts/gerar-credenciais.sh`: gera uma única vez o `.env` (senhas de root, banco, admin e Basic Auth dos 10 grupos) e o `credenciais.txt`; não sobrescreve se já existir.
- Novo `scripts/reset-grupo.sh N`: devolve um grupo à loja recém-instalada (banco e arquivos), mantendo as mesmas credenciais.
- **BREAKING** Removidos `grupos.sh`, `exportar-modelo.sh` e a pasta `seed/`; `envs/`, `auth/` e `credenciais.txt` atuais são substituídos pelos novos.
- **BREAKING** Fim dos 10 projetos compose separados (`-p grupoN`) com 10 MariaDBs; volumes antigos não são migrados.

## Capabilities

### New Capabilities
- `zencart-provisioning`: provisionamento automático das 10 lojas (instalação sem intervenção, isolamento de banco por grupo, admin em `/manage`, geração de credenciais e reset de um grupo).

### Modified Capabilities
<!-- nenhuma: não há specs existentes em openspec/specs/ -->

## Impact

- **Arquivos novos/alterados:** `docker-compose.yml`, `docker/web/Dockerfile`, `docker/web/zc-entrypoint.sh`, `docker/web/zc-admin.php` (ou equivalente no provisionamento do banco), script de initdb/provisionamento do MariaDB, `scripts/gerar-credenciais.sh`, `scripts/reset-grupo.sh`.
- **Arquivos removidos:** `grupos.sh`, `exportar-modelo.sh`, `seed/`, `envs/` (substituído por `.env`).
- **Organização:** arquivos de container em `docker/web/` e `docker/db/init/`, comandos em `scripts/`, `docker-compose.yml` e novo `README.md` na raiz.
- **Infra:** de 20 containers (10 web + 10 db) para 11 (10 web + 1 db); portas mantidas em 8012..8021.
- **Operação:** um MariaDB fora do ar derruba as 10 lojas; consultas pesadas de um grupo afetam os demais.
- **Dependências:** nenhuma nova; continua `php:8.2-apache`, `mariadb:10.11` e Zen Cart 2.1.0 baixado do GitHub no build.
