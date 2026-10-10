## 1. Imagem web

- [x] 1.1 No `docker/web/Dockerfile`, instalar `openssh-server` e criar `/run/sshd`; verificar com `docker run --rm --entrypoint sshd zencart-local:2.1.0 -t -f /etc/ssh/sshd_config` retornando 0
- [x] 1.2 Criar `docker/web/sshd_config` (porta 22, `PermitRootLogin no`, `PasswordAuthentication yes`, sem encaminhamentos, `HostKey /etc/ssh/ssh_host_ed25519_key`, `AllowUsers` definido pelo entrypoint) e copiá-lo na imagem; verificar com `sshd -t` dentro do container em execução
- [x] 1.3 Ajustar Apache para 256 MB: `mpm_prefork` (StartServers 2, Min/MaxSpare 2/4, MaxRequestWorkers 8, MaxConnectionsPerChild 500) e `umask 002` em `/etc/apache2/envvars`; verificar com `apachectl -t` e `grep` dos valores na imagem
- [x] 1.4 Em `docker/web/php.ini`, `memory_limit = 96M`; verificar com `php -i | grep memory_limit` no container

## 2. Cota e comando limites

- [x] 2.1 Criar `docker/web/zc-cota.sh` (loop a cada `QUOTA_CHECK_SECONDS`, padrão 300: `du -sb` → `/run/zc/cota.uso`; acima de `DISK_QUOTA_MB` cria `zz-cota.ini` com `file_uploads = Off` + `apachectl graceful`; abaixo remove; graceful só na mudança de estado); verificar com `bash -n` e pelo teste 5.5
- [x] 2.2 Criar `docker/web/limites` (CPU de `cpu.max` + uso por `cpu.stat`, RAM de `memory.current`/`memory.max`, disco de `/run/zc/cota.uso`/cota, estado dos uploads, tamanho do banco via `~/.my.cnf`) e `/etc/profile.d/zz-limites.sh` chamando-o no login; verificar com `bash -n` e pelo teste 5.4

## 3. Entrypoint

- [x] 3.1 Na instalação da loja (bloco do marcador), aplicar `chgrp -R www-data`, `chmod -R g+w` e `g+s` nas pastas de `/var/www/html`; verificar com `stat` em um arquivo e uma pasta após a instalação
- [x] 3.2 A cada subida: gravar `/etc/zc/limites.conf` (GRUPO, DISK_QUOTA_MB, DB_DATABASE); criar o usuário do grupo (home `/home/grupoN`, grupo `www-data`, senha de `SSH_PASSWORD`, link `loja -> /var/www/html`, `~/.my.cnf` 600); copiar a chave de host de `/run/zc-ssh-host` para `/etc/ssh` (root, 600); escrever `AllowUsers`; iniciar `sshd`; iniciar `zc-cota.sh` em segundo plano; verificar com `bash -n` e `docker compose logs` sem erro

## 4. Compose, credenciais e reset

- [x] 4.1 `docker-compose.yml`: em `x-web`, `deploy.resources.limits` (cpus 0.5, memory 256M) e `DISK_QUOTA_MB: 2048`; por grupo, porta `22NN:22` (2212..2221), `SSH_PASSWORD: ${GRUPON_SSH_PASSWORD:?...}` e `./ssh:/run/zc-ssh-host:ro`; verificar com `docker compose config -q` e `docker inspect` (NanoCpus=500000000, Memory=268435456)
- [x] 4.2 `scripts/gerar-credenciais.sh`: gerar `GRUPON_SSH_PASSWORD`, criar `ssh/ssh_host_ed25519_key` (se ausente) e adicionar `ssh=`, `ssh_usuario=`, `ssh_senha=` ao `credenciais.txt`; verificar em cópia temporária que os campos existem e que a segunda execução não altera `.env` nem a chave
- [x] 4.3 `.gitignore`: adicionar `ssh/`; verificar com `git check-ignore ssh/ssh_host_ed25519_key`
- [x] 4.4 Migrar o ambiente local: `docker compose down -v`, apagar `.env`, `auth/`, `credenciais.txt`, gerar credenciais e `docker compose up -d --build`; verificar 11 containers em execução e 10 lojas instaladas nos logs

## 5. Validação de ponta a ponta

- [x] 5.1 Regressão: para os 10 grupos, 401 sem senha, 200 com senha, `/admin` e `/zc_install` 404, 1º login no `/manage` cai no "Admin Home"
- [x] 5.2 SSH: login do grupo3 na 2214 funciona; senha errada, usuário de outro grupo e `root` são recusados; `sudo`/escrita em `/etc` negados; `ssh -L` recusado
- [x] 5.3 Permissões e banco: pelo SSH, criar/editar/apagar arquivo na loja (inclusive um enviado pelo Apache); `mariadb -e 'SELECT 1'` conecta ao próprio banco; `USE zc_grupo2` negado
- [x] 5.4 `limites`: mostra CPU 0.5, RAM x/256 MB, disco x/2048 MB, uploads liberados e tamanho do banco; aparece no login SSH
- [x] 5.5 Cota: subir com `DISK_QUOTA_MB` baixo e `QUOTA_CHECK_SECONDS` curto num grupo de teste (override), ultrapassar com um arquivo grande → upload pelo admin recusado e `limites` mostra BLOQUEADOS; apagar o arquivo → uploads voltam; restaurar valores padrão
- [x] 5.6 Carga: 20 requisições simultâneas (vitrine + admin) por 60 s num grupo; `docker stats` ≤ 256 MB, sem OOM (`docker inspect` OOMKilled=false, sem restarts) e as outras lojas respondem
- [x] 5.7 Reset: `./scripts/reset-grupo.sh 4 -y` mantém senhas de Basic Auth, admin e SSH, e `ssh` não alerta mudança de chave de host

## 6. Documentação

- [x] 6.1 Atualizar `README.md` (portas SSH, limites, cota, `limites`), `scripts/README.md` (novos campos e chave SSH) e `docker/README.md` (sshd, cota, `limites`, Apache/PHP, novas variáveis); verificar links e que nenhum valor diverge do compose
