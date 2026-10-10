## Context

Arquitetura atual: ver `openspec/specs/zencart-provisioning/spec.md` e `docker/README.md` (1 MariaDB + 10 containers web, imagem única, entrypoint que instala a loja). Motivação: ver proposal.md.

Fatos verificados em spike (2026-10-10):

- Host com cgroup v2: `deploy.resources.limits` funciona; dentro do container, `/sys/fs/cgroup/memory.max` mostra `268435456` e `cpu.max` mostra `50000 100000` (0.5 CPU). Já `nproc`, `free` e `top` mostram a máquina inteira (16 CPUs, 15 GB), daí a necessidade do comando `limites`.
- Limite rígido de disco não é viável sem root no host: o driver `local` do Docker monta volumes via syscall e recusa `o=loop` (`loop: invalid argument`); `storage_opt size=` exige XFS e o host é ext4. O usuário escolheu cota suave (sem `sudo`, portátil).
- Apache usa `mpm_prefork` com `MaxRequestWorkers 150` e o PHP tem `memory_limit 256M`, valores incompatíveis com um container de 256 MB.

## Goals / Non-Goals

**Goals:**
- Limites de recurso declarados só no `docker-compose.yml`, iguais para as 10 lojas.
- SSH e cota sem nenhuma etapa com `sudo` no host; o projeto continua "gerou credenciais, subiu".
- O grupo enxerga os próprios limites e usos com um único comando.

**Non-Goals:**
- Limite rígido de disco e cota do banco.
- Limites para o container `db`.
- Isolar as lojas entre si na rede `frontend` (continua como hoje).
- Bloquear escrita por SSH acima da cota (a cota bloqueia uploads pela loja; o SSH só mostra o aviso).
- Supervisor de processos (sshd e o verificador de cota não são reiniciados se morrerem; o container sim, pelo `restart`).

## Decisions

### 1. Limites via `deploy.resources.limits` no bloco `x-web`

`cpus: "0.5"` e `memory: 256M` no bloco comum, herdado pelos 10 serviços. É o formato padrão do Compose v2 (aplicado fora do Swarm) e fica num único lugar.

- *Alternativa:* `cpus:`/`mem_limit:` no nível do serviço. Equivalente, mas `deploy.resources` é o formato atual da especificação.

### 2. Apache e PHP dimensionados para 256 MB

- `mpm_prefork`: `StartServers 2`, `MinSpareServers 2`, `MaxSpareServers 4`, `MaxRequestWorkers 8`, `MaxConnectionsPerChild 500` (recicla processos e limita vazamento de memória).
- PHP `memory_limit` de 256M para **96M**.

Conta: 8 workers × ~25 MB típicos ≈ 200 MB no pior caso comum, sobrando para sshd, sessões SSH e o verificador de cota. Validado por teste de carga (tasks). Se o teste mostrar OOM, ajustar `MaxRequestWorkers` para baixo antes de mexer no limite de RAM.

### 3. Cota suave de 2 GB: verificador dentro do container

`zc-cota.sh` roda em segundo plano, iniciado pelo entrypoint, em loop a cada `QUOTA_CHECK_SECONDS` (padrão 300):

1. `du -sb /var/www/html` → grava o uso em `/run/zc/cota.uso` (lido pelo `limites`).
2. Acima de `DISK_QUOTA_MB` (padrão 2048): cria `/usr/local/etc/php/conf.d/zz-cota.ini` com `file_uploads = Off` e faz `apachectl graceful`.
3. Abaixo: remove o arquivo e faz `graceful`, só quando o estado muda.

`file_uploads = Off` faz o PHP descartar arquivos enviados: vitrine e admin continuam navegáveis, só o upload falha. A medição cobre toda a pasta da loja (inclui ~42 MB do próprio Zen Cart), o que é simples e conservador.

- *Alternativa:* cron no host. Rejeitada: exige configurar o host, e o projeto deve ser só `docker compose`.
- *Alternativa:* tirar permissão de escrita das pastas. Rejeitada: impediria o grupo de apagar arquivos para liberar espaço.

### 4. SSH: sshd no mesmo container da loja

- `openssh-server` instalado na imagem; o entrypoint inicia `/usr/sbin/sshd` (que vira daemon) antes de passar o controle ao Apache.
- O entrypoint cria a cada subida o usuário `grupoN` (o sistema de arquivos do container é efêmero): `useradd` com home `/home/grupoN`, shell bash, grupo suplementar `www-data`, senha de `SSH_PASSWORD` via `chpasswd`.
- `sshd_config` próprio: `PermitRootLogin no`, `AllowUsers` com o usuário do grupo, `PasswordAuthentication yes`, `AllowTcpForwarding no`, `X11Forwarding no`, `AllowAgentForwarding no`, `PermitTunnel no`.
- Home fora do docroot (`/home/grupoN`), com o link `loja -> /var/www/html`, para que `.bash_history` e outros dotfiles nunca fiquem acessíveis pela web.
- Container separado só para SSH foi rejeitado: teria uma visão diferente de CPU/RAM (os limites que o grupo quer ver são os da loja) e precisaria compartilhar o volume.

### 5. Permissões: o grupo edita o que o Apache escreve

- Arquivos da loja pertencem a `www-data:www-data`, com escrita de grupo (`g+w` em tudo e `g+s` nas pastas, para novos arquivos herdarem o grupo).
- O Apache roda com `umask 002` (em `/etc/apache2/envvars`), para que uploads também nasçam com escrita de grupo.
- O usuário `grupoN` está no grupo `www-data`: lê, cria, edita e apaga, sem ser root.
- O entrypoint aplica `chgrp`/`chmod` uma vez, só na instalação, para não varrer o volume a cada subida.

### 6. Banco pelo SSH: `~/.my.cnf` com as credenciais do próprio grupo

O entrypoint grava `/home/grupoN/.my.cnf` (modo 600, dono `grupoN`) com host `db`, usuário e senha do grupo e `skip-ssl`. Assim `mariadb` conecta direto ao próprio banco, e o `limites` usa o mesmo arquivo para medir o tamanho do banco. O isolamento continua garantido pelo GRANT. A senha é só do próprio grupo, que já tem acesso total a esse banco.

### 7. Comando `limites`

Script `/usr/local/bin/limites`, também chamado por `/etc/profile.d/zz-limites.sh` no login:

| Linha | Fonte |
|---|---|
| CPU: limite e uso recente | `cpu.max`; uso por delta de `cpu.stat usage_usec` em 1 s |
| RAM: em uso / limite | `memory.current` / `memory.max` |
| Disco: em uso / cota | `/run/zc/cota.uso` (medido pelo verificador) / `DISK_QUOTA_MB` |
| Uploads | `liberados` ou `BLOQUEADOS (cota excedida)`, pela presença de `zz-cota.ini` |
| Banco | `SUM(data_length+index_length)` de `information_schema.tables` via `~/.my.cnf` |

As sessões SSH não herdam as variáveis do container. Por isso o entrypoint grava `/etc/zc/limites.conf` (legível por todos, sem segredos) com `GRUPO`, `DISK_QUOTA_MB` e `DB_DATABASE`.

### 8. Chave de host SSH gerada no host e montada só para leitura

`gerar-credenciais.sh` cria `ssh/ssh_host_ed25519_key` uma vez (ignorada pelo git). O compose a monta em `/run/zc-ssh-host` como somente leitura, e o entrypoint copia para `/etc/ssh/` com dono root e modo 600 (o sshd recusa chaves com dono diferente de root ou permissões abertas). Mesma chave para os 10 grupos (é o mesmo servidor), estável entre recriações, resets e rebuilds.

- *Alternativa:* gerar a chave no build. Rejeitada: muda a cada rebuild e dispara o alerta "REMOTE HOST IDENTIFICATION HAS CHANGED".

### 9. Portas e credenciais

- SSH do grupoN em `2211 + N` (2212..2221), escrito literalmente no compose, como as portas HTTP.
- `.env` ganha `GRUPON_SSH_PASSWORD` (12 hex). `credenciais.txt` ganha `ssh=ssh grupoN@<ip> -p <porta>`, `ssh_usuario` e `ssh_senha`.
- Nenhuma credencial nova para o reset: tudo vem do `.env` e de `ssh/`, que o reset não toca.

## Risks / Trade-offs

- [RAM de 256 MB estourar sob carga, com o container reiniciado pelo OOM killer] → prefork limitado a 8 workers, PHP 96M, teste de carga nas tasks; o `limites` mostra o uso real para o grupo acompanhar.
- [Cota suave: o grupo pode passar de 2 GB entre verificações ou gravando direto pelo SSH] → intervalo de 5 min; uploads pela loja são bloqueados assim que detectado; é a limitação aceita ao recusar `sudo`.
- [sshd ou verificador de cota morrem sem reinício] → processos simples e de baixo consumo; reiniciar o container (`docker compose restart grupoN`) restaura tudo.
- [Shell dentro do container amplia a superfície de ataque] → usuário sem root, encaminhamento desativado, banco isolado por GRANT, rede de laboratório; documentado no README.
- [Aluno vê as variáveis de ambiente do Apache?] → `/proc/<pid>/environ` de processos root/www-data não é legível por `grupoN`; os segredos que ele acessa são só os do próprio grupo (`.my.cnf`).
- [`du` periódico em lojas grandes] → no máximo uma varredura a cada 5 min de uma pasta limitada a ~2 GB; custo desprezível.

## Migration Plan

1. O `.env` atual não tem `GRUPON_SSH_PASSWORD` e o compose novo a exige **até para o `down`** (a interpolação falha antes de qualquer ação). As lojas atuais estão vazias, então: derrubar com valores provisórios (`env GRUPO1_SSH_PASSWORD=x … GRUPO10_SSH_PASSWORD=x docker compose down -v`, ou rodar o `down -v` antes de atualizar o código), apagar `.env`, `auth/` e `credenciais.txt`, rodar `./scripts/gerar-credenciais.sh` e `docker compose up -d --build`.
2. Validar com os testes de ponta a ponta das tasks.

Rollback: `git checkout` da versão anterior, mais os mesmos passos do item 1 (o `.env` antigo continua compatível com a versão anterior, porque só ganha variáveis novas).
