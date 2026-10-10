# Lojas Zen Cart por grupo

Sobe **10 lojas Zen Cart 2.1.0 independentes** (grupo1 a grupo10), já instaladas e prontas para uso, com um único `docker compose up`. Cada grupo tem sua loja, seu painel administrativo, seu banco de dados isolado e sua senha de acesso.

Não há instalação manual: o instalador web do Zen Cart nunca aparece.

## Requisitos

- Docker com o plugin Compose (`docker compose version`)
- `openssl` no host (usado para gerar as senhas)
- Cerca de 1,5 GB de RAM livre e as portas **8012 a 8021** disponíveis

## Início rápido

```bash
./scripts/gerar-credenciais.sh      # 1x: cria .env, auth/ e credenciais.txt
docker compose up -d --build        # sobe o banco e as 10 lojas
```

A primeira subida leva alguns minutos (build da imagem + instalação dos 10 bancos). Depois disso, abra `http://<ip-do-servidor>:8012` e entre com o usuário e a senha do `[grupo1]` em `credenciais.txt`.

## Endereços

| Grupo | Loja | Painel admin |
|---|---|---|
| grupoN | `http://<servidor>:<8011+N>` | `http://<servidor>:<8011+N>/manage` |
| grupo1 | `:8012` | `:8012/manage` |
| grupo10 | `:8021` | `:8021/manage` |

Todo acesso pede antes o login do navegador (Basic Auth) do grupo. Depois, o painel `/manage` pede o login de admin do Zen Cart. Os dois estão em `credenciais.txt`.

## Estrutura da pasta

```
.
+-- docker-compose.yml          define o banco + as 10 lojas
+-- README.md
|
+-- docker/                     tudo que entra nos containers (ver docker/README.md)
|   +-- README.md
|   +-- web/                    imagem das lojas (php 8.2 + apache + Zen Cart)
|   |   +-- Dockerfile
|   |   +-- zc-entrypoint.sh    instala a loja no banco do grupo na 1a subida
|   |   +-- zc-admin.php        define usuário/senha do admin
|   |   +-- zc-configure.php    gera os configure.php no build
|   |   +-- php.ini
|   |   +-- auth.conf           Basic Auth do Apache
|   +-- db/
|       +-- init/01-grupos.sh   cria os 10 bancos e usuários (1a subida do MariaDB)
|
+-- scripts/                    comandos de operação (ver scripts/README.md)
|   +-- README.md
|   +-- gerar-credenciais.sh
|   +-- reset-grupo.sh
|
+-- .env                        GERADO - senhas usadas pelo compose (não distribuir)
+-- credenciais.txt             GERADO - acessos para entregar aos grupos
+-- auth/                       GERADO - grupoN.htpasswd (Basic Auth)
```

Os itens marcados **GERADO** são criados por `scripts/gerar-credenciais.sh` e contêm segredos. Guarde-os com cuidado e não os versione.

**Documentação detalhada:**

- [scripts/README.md](scripts/README.md): o que cada script cria ou apaga, opções, senhas geradas e comandos manuais úteis.
- [docker/README.md](docker/README.md): o que acontece no build, na 1ª subida do banco e em cada subida das lojas; o papel de cada arquivo e as variáveis de ambiente.

## Operação do dia a dia

| Quero... | Comando |
|---|---|
| Ver o estado | `docker compose ps` |
| Parar tudo (mantém os dados) | `docker compose down` |
| Subir de novo | `docker compose up -d` |
| Ver logs de um grupo | `docker compose logs -f grupo3` |
| Reiniciar um grupo | `docker compose restart grupo3` |
| Zerar a loja de um grupo | `./scripts/reset-grupo.sh 3` |
| Apagar **tudo** (todas as lojas e bancos) | `docker compose down -v` |

### Resetar um grupo

```bash
./scripts/reset-grupo.sh 3        # pede para digitar "grupo3" como confirmação
./scripts/reset-grupo.sh 3 -y     # sem confirmação
```

Apaga o banco e os arquivos (imagens enviadas, plugins) **só daquele grupo** e reinstala a loja do zero. As senhas continuam as mesmas, então o `credenciais.txt` já entregue segue valendo. Os outros grupos não são afetados.

## Credenciais

`./scripts/gerar-credenciais.sh` gera senhas aleatórias e **nunca sobrescreve** as existentes. Se `.env` já existir, ele avisa e não faz nada.

Para cada grupo, o `credenciais.txt` traz:

```
[grupo1]
loja=http://<ip-do-servidor>:8012
usuario=grupo1          <- login do navegador (Basic Auth)
senha=...
admin=http://<ip-do-servidor>:8012/manage
admin_usuario=grupo1    <- login do painel Zen Cart
admin_senha=...
```

A senha de root do banco e as senhas de banco dos grupos ficam só no `.env`. Os grupos não precisam delas.

### IP do servidor e acesso pela rede

As lojas **não dependem de IP configurado**: os links são montados com o endereço digitado no navegador. Por isso o projeto funciona em qualquer computador, e qualquer aparelho da mesma rede acessa por `http://<ip-da-máquina>:8012`.

O `gerar-credenciais.sh` detecta o IP da máquina na rede local e o escreve nas URLs do `credenciais.txt`. Isso vale só para o texto do arquivo e não fixa nada nas lojas. Se a detecção falhar, as URLs aparecem como `<ip-do-servidor>`.

Se o IP da máquina mudar (por exemplo, em outra rede ou outro computador), as lojas continuam funcionando. Basta atualizar o texto, sem gerar senhas novas:

```bash
sed -i 's/192.168.1.16/<ip-novo>/' credenciais.txt   # troque pelos IPs antigo e novo
```

Dica: reserve o IP da máquina no roteador (DHCP estático) para ele não mudar entre as aulas.

**Avançado: forçar um endereço fixo.** `HOST=192.168.0.10 ./scripts/gerar-credenciais.sh` grava o endereço no `.env`, e as lojas passam a usá-lo sempre. Evite essa opção se o projeto for mudar de máquina. Com credenciais já existentes, ela exige gerar senhas novas: apague `.env`, `auth/` e `credenciais.txt`, rode o comando e depois `docker compose down -v && docker compose up -d`.

## Como funciona

```
 docker compose up -d
   |
   +-- db (MariaDB 10.11, rede interna, sem porta exposta)
   |     1a subida: docker/db/init/01-grupos.sh
   |       para N=1..10: banco zc_grupoN + usuário grupoN
   |                     (acesso só ao próprio banco)
   |
   +-- grupo1 .. grupo10 (mesma imagem zencart-local:2.1.0)
         build:  Zen Cart baixado, admin renomeado para /manage,
                 zc_install removido, configure.php lendo o ambiente
         subida: se o banco do grupo ainda não tem a loja,
                 importa o SQL oficial e define o admin
         volume: grupoN_files guarda os arquivos de cada loja
```

- **Isolamento:** todos os bancos rodam no mesmo MariaDB, mas cada usuário `grupoN` só enxerga `zc_grupoN`.
- **Persistência:** dados ficam nos volumes `zencart_db_data` e `zencart_grupoN_files`. `down` mantém, `down -v` apaga.
- **Sem dados de demonstração:** as lojas começam com o catálogo vazio.

## Problemas comuns

**`required variable ... is missing a value: rode ./scripts/gerar-credenciais.sh`**
O `.env` não existe. Rode `./scripts/gerar-credenciais.sh`.

**A loja não abre logo após o `up`**
Na primeira subida, cada loja espera o banco e importa o SQL. Acompanhe com `docker compose logs -f grupo1` até aparecer `admin 'grupo1' configurado`.

**Grupo esqueceu a senha do admin**
Rode `docker compose exec grupoN php /usr/local/bin/zc-admin.php` (troque N pelo número do grupo). A senha do admin volta a ser a do `credenciais.txt`, sem apagar dados.

**Mudei algo em `docker/web/` e as lojas não mudaram**
Rode `docker compose up -d --build`. Os arquivos de lojas já criadas ficam no volume de cada grupo, então mudanças no código do Zen Cart só valem para grupos resetados.

## Segurança

- O acesso é HTTP sem TLS. Use em rede local ou de laboratório.
- `.env` e `credenciais.txt` são criados com permissão `600`. Distribua a cada grupo só o bloco dele.
- O banco não tem porta publicada no host.
