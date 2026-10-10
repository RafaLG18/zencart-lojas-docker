# zencart-provisioning Specification

## Purpose

Provisionar automaticamente 10 lojas Zen Cart 2.1.0 independentes, uma por grupo de alunos, prontas para uso logo após subir o ambiente com Docker Compose, sem instalação manual, e permitir devolver qualquer grupo ao estado recém-instalado.

## Requirements

### Requirement: Lojas prontas sem instalação manual
O ambiente SHALL entregar as 10 lojas (grupo1..grupo10) já instaladas após `docker compose up -d`, sem exibir o instalador do Zen Cart e sem nenhum passo manual em navegador.

#### Scenario: Primeira subida
- **WHEN** o operador gera as credenciais e executa `docker compose up -d` pela primeira vez
- **THEN** cada uma das 10 lojas responde com a vitrine do Zen Cart 2.1.0 em sua porta, sem redirecionar para `zc_install`

#### Scenario: Subidas seguintes preservam os dados
- **WHEN** o ambiente é parado e iniciado novamente sem remover volumes
- **THEN** produtos, pedidos e configurações cadastrados pelos grupos permanecem intactos

### Requirement: Loja inicia sem dados de demonstração
Cada loja SHALL iniciar com a estrutura e a configuração padrão do Zen Cart, sem produtos, categorias ou imagens de demonstração.

#### Scenario: Catálogo vazio
- **WHEN** um grupo acessa sua loja recém-provisionada
- **THEN** o catálogo não contém nenhum produto nem categoria

### Requirement: Banco isolado por grupo
Cada grupo SHALL ter um banco de dados próprio e um usuário de banco próprio, e esse usuário MUST ter acesso apenas ao banco do seu grupo, ainda que todos os bancos estejam no mesmo servidor MariaDB.

#### Scenario: Acesso ao próprio banco
- **WHEN** a loja do grupoN se conecta ao banco com o usuário do grupoN
- **THEN** ela lê e grava normalmente no banco do grupoN

#### Scenario: Acesso negado ao banco de outro grupo
- **WHEN** o usuário de banco do grupoN tenta acessar o banco de qualquer outro grupo
- **THEN** o servidor recusa o acesso

#### Scenario: Banco fora do alcance externo
- **WHEN** alguém tenta se conectar ao MariaDB a partir de fora do ambiente Docker
- **THEN** não há porta de banco exposta no host e a conexão não é possível

### Requirement: Porta fixa por grupo
A loja do grupoN SHALL ser servida na porta `8011 + N` do host (grupo1 = 8012 … grupo10 = 8021).

#### Scenario: Endereço do grupo
- **WHEN** um aluno do grupo3 abre `http://<servidor>:8014`
- **THEN** recebe a loja do grupo3

### Requirement: Loja funciona pelo endereço usado no navegador
Os links gerados pela loja e pelo admin SHALL usar um endereço base configurado, quando existir, ou o endereço pelo qual o navegador acessou a loja.

#### Scenario: Acesso por IP sem endereço configurado
- **WHEN** nenhum endereço base está configurado e o aluno acessa a loja por `http://192.168.0.10:8012`
- **THEN** os links da vitrine e do admin apontam para `http://192.168.0.10:8012`

### Requirement: Acesso protegido por Basic Auth do grupo
Toda requisição à loja e ao admin de um grupo SHALL exigir o usuário e a senha de Basic Auth daquele grupo.

#### Scenario: Sem credencial
- **WHEN** alguém acessa a porta de um grupo sem informar usuário e senha
- **THEN** recebe HTTP 401

#### Scenario: Credencial de outro grupo
- **WHEN** alguém acessa a loja do grupo2 com o usuário e senha de Basic Auth do grupo1
- **THEN** recebe HTTP 401

### Requirement: Admin em /manage com login próprio do grupo
O painel administrativo de toda loja SHALL estar em `/manage`, com o instalador ausente, e MUST aceitar o usuário e a senha de admin gerados para aquele grupo, sem bloquear o acesso por pasta de admin não renomeada ou instalador presente.

#### Scenario: Login no admin
- **WHEN** o grupoN acessa `http://<servidor>:<porta>/manage` e informa o usuário e a senha de admin do grupoN
- **THEN** entra no painel administrativo sem ser forçado a trocar a senha

#### Scenario: Caminhos padrão inexistentes
- **WHEN** alguém autenticado no Basic Auth acessa `/admin` ou `/zc_install` em qualquer loja
- **THEN** recebe HTTP 404

#### Scenario: Senha de admin alterada pelo grupo persiste
- **WHEN** o grupo altera a senha do admin pelo painel e o ambiente é reiniciado
- **THEN** a nova senha continua valendo

### Requirement: Geração de credenciais
O ambiente SHALL fornecer um comando que gera, uma única vez, senhas aleatórias de root do banco e, para cada grupo, senhas de banco, admin e Basic Auth, gravando-as para uso do Docker Compose e num arquivo `credenciais.txt` para o professor distribuir.

#### Scenario: Primeira geração
- **WHEN** o operador executa o comando de geração sem credenciais existentes
- **THEN** são criadas credenciais distintas para os 10 grupos e `credenciais.txt` lista, por grupo, a URL da loja, o usuário e a senha de Basic Auth, e a URL, o usuário e a senha do admin

#### Scenario: Geração repetida não sobrescreve
- **WHEN** o operador executa o comando de geração e as credenciais já existem
- **THEN** nenhuma senha é alterada e o comando informa que as credenciais já existem

#### Scenario: Senha de root fora do arquivo dos grupos
- **WHEN** o professor distribui o `credenciais.txt`
- **THEN** o arquivo não contém a senha de root do banco nem as senhas de banco dos grupos

#### Scenario: Subir sem credenciais
- **WHEN** o operador executa `docker compose up -d` sem ter gerado as credenciais
- **THEN** o Compose falha com mensagem indicando que as credenciais precisam ser geradas

### Requirement: Reset de um grupo
O ambiente SHALL fornecer um comando que devolve a loja de um único grupo ao estado recém-instalado (banco e arquivos), mantendo as mesmas credenciais e sem afetar os demais grupos.

#### Scenario: Reset do grupo informado
- **WHEN** o operador executa o reset para o grupo4 e confirma
- **THEN** a loja do grupo4 volta ao estado recém-instalado, sem os dados cadastrados pelo grupo, e aceita as mesmas credenciais de Basic Auth e admin de antes

#### Scenario: Outros grupos intactos
- **WHEN** o reset do grupo4 é concluído
- **THEN** os dados e a disponibilidade das lojas dos demais grupos não são alterados

#### Scenario: Confirmação obrigatória
- **WHEN** o operador executa o reset sem confirmar a operação
- **THEN** nada é apagado

#### Scenario: Grupo inválido
- **WHEN** o operador executa o reset com um número fora de 1..10
- **THEN** o comando falha com mensagem de uso e nada é apagado
