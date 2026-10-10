# group-ssh-access Specification

## Purpose

Dar a cada grupo acesso por SSH ao container da própria loja, sem privilégios de administrador, para inspecionar e editar os arquivos da loja e conferir o uso e os limites de CPU, memória, armazenamento e banco.

## Requirements

### Requirement: Acesso SSH por grupo
Cada grupo SHALL poder entrar por SSH no container da própria loja na porta `2211 + N` do host (grupo1 = 2212 … grupo10 = 2221), com o usuário `grupoN` e a senha SSH do grupo.

#### Scenario: Login com a credencial do grupo
- **WHEN** um aluno executa `ssh grupo3@<servidor> -p 2214` e informa a senha SSH do grupo3
- **THEN** obtém um shell dentro do container da loja do grupo3

#### Scenario: Senha errada ou usuário de outro grupo
- **WHEN** alguém tenta entrar na porta do grupo3 com senha errada ou com o usuário de outro grupo
- **THEN** o login é recusado

#### Scenario: Login como root recusado
- **WHEN** alguém tenta entrar por SSH como `root`
- **THEN** o login é recusado

### Requirement: Usuário SSH sem privilégios de administrador
O usuário SSH do grupo MUST NOT ter privilégios de root no container, e SHALL poder ler, criar, editar e apagar os arquivos da própria loja.

#### Scenario: Sem root
- **WHEN** o aluno, logado por SSH, tenta executar um comando que exige root
- **THEN** o comando é negado

#### Scenario: Edição dos arquivos da loja
- **WHEN** o aluno edita ou cria um arquivo dentro da pasta da loja
- **THEN** a alteração é gravada e aparece na loja

#### Scenario: Arquivo enviado pela loja editável por SSH
- **WHEN** um arquivo é enviado pelo admin da loja e depois o aluno tenta apagá-lo por SSH
- **THEN** o arquivo é apagado

### Requirement: Isolamento entre grupos via SSH
A partir do shell SSH, o grupo MUST ter acesso apenas ao próprio banco e MUST NOT conseguir usar o SSH como túnel para outros serviços.

#### Scenario: Acesso ao próprio banco
- **WHEN** o aluno executa o cliente de banco a partir do shell SSH
- **THEN** conecta ao banco do próprio grupo sem precisar informar senha

#### Scenario: Banco de outro grupo negado
- **WHEN** o aluno tenta acessar o banco de outro grupo a partir do shell SSH
- **THEN** o servidor recusa o acesso

#### Scenario: Encaminhamento de portas desativado
- **WHEN** o aluno tenta abrir um túnel SSH (encaminhamento de porta)
- **THEN** o túnel é recusado

### Requirement: Comando limites
O container SHALL oferecer o comando `limites`, que mostra para o grupo: limite de CPU, RAM em uso e limite de RAM, uso de disco dos arquivos da loja e cota, se o envio de arquivos está liberado ou bloqueado, e o tamanho do banco do grupo. O mesmo resumo SHALL ser exibido ao entrar por SSH.

#### Scenario: Consulta dos limites
- **WHEN** o aluno executa `limites`
- **THEN** vê CPU limite 0.5, RAM em uso de 256 MB, disco em uso de 2 GB, estado dos uploads e o tamanho do banco

#### Scenario: Resumo no login
- **WHEN** o aluno entra por SSH
- **THEN** o resumo dos limites aparece antes do prompt

#### Scenario: Cota excedida visível
- **WHEN** os arquivos da loja estão acima da cota
- **THEN** `limites` indica que o envio de arquivos está bloqueado por cota excedida

### Requirement: Chave de host SSH estável
A identidade SSH do servidor SHALL permanecer a mesma entre reinícios, recriações de container e resets, para que o aluno não receba alerta de chave alterada.

#### Scenario: Reset não altera a chave de host
- **WHEN** um aluno já conectou ao grupo4 e o grupo4 é resetado
- **THEN** a próxima conexão SSH não exibe alerta de chave de host alterada
