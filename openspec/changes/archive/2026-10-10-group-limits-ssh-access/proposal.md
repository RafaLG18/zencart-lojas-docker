## Why

Hoje cada loja pode usar toda a CPU, RAM e disco do servidor, e os grupos não têm como ver o que estão consumindo. Para a aula, cada grupo precisa de uma fatia fixa e conhecida da máquina e de um jeito de inspecionar a própria loja por dentro, via SSH, conferindo seus limites de CPU, memória e armazenamento.

## What Changes

- Cada loja passa a ter **limite de 0.5 CPU e 256 MB de RAM**.
- Cada loja passa a ter uma **cota suave de 2 GB** para os arquivos da loja. Ao ultrapassar, o envio de arquivos pela loja é bloqueado até o uso voltar para baixo da cota. O banco não entra na cota.
- **Acesso SSH por grupo**: porta própria (2212..2221), usuário `grupoN` sem privilégio de root, com acesso de escrita aos arquivos da própria loja e ao próprio banco.
- Novo comando **`limites`** dentro do container, exibido também ao entrar por SSH: CPU, RAM (uso/limite), disco (uso/cota), estado dos uploads e tamanho do banco.
- Apache e PHP ajustados para caber em 256 MB (menos processos, `memory_limit` menor).
- `gerar-credenciais.sh` passa a gerar também a senha SSH de cada grupo e a chave de host SSH; `credenciais.txt` ganha o acesso SSH.
- **BREAKING** O `.env` atual não tem senhas SSH: é preciso gerar credenciais novas e recriar o ambiente (as lojas atuais estão vazias).

## Capabilities

### New Capabilities
- `group-ssh-access`: acesso SSH por grupo ao container da própria loja, sem root, com o comando `limites` para ver uso e limites de CPU, RAM, disco e banco.

### Modified Capabilities
- `zencart-provisioning`: adiciona limites de CPU/RAM e cota de armazenamento por loja; a geração de credenciais e o reset passam a incluir o acesso SSH.

## Impact

- **Arquivos:** `docker-compose.yml`, `docker/web/Dockerfile`, `docker/web/zc-entrypoint.sh`, `docker/web/php.ini`, novos scripts em `docker/web/` (cota, `limites`, config do sshd/Apache), `scripts/gerar-credenciais.sh`, `scripts/reset-grupo.sh`, `.gitignore`, READMEs.
- **Rede:** 10 novas portas publicadas no host (2212..2221).
- **Segurança:** os grupos passam a ter shell dentro do próprio container (sem root); a chave de host SSH fica em `ssh/` (gerada, fora do git).
- **Capacidade:** pior caso das 10 lojas = 5 CPUs e 2,5 GB de RAM; a máquina atual tem 16 CPUs e 15 GB.
