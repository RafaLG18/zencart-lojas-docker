## ADDED Requirements

### Requirement: Limites de CPU e memória por loja
Cada loja SHALL rodar limitada a no máximo 0.5 CPU e 256 MB de RAM, sem afetar o limite das demais lojas.

#### Scenario: Limites aplicados
- **WHEN** o ambiente está em execução
- **THEN** cada uma das 10 lojas tem limite de 0.5 CPU e 256 MB de RAM

#### Scenario: Loja sob carga continua dentro do limite
- **WHEN** uma loja recebe várias requisições simultâneas na vitrine e no admin
- **THEN** a loja continua respondendo sem ultrapassar 256 MB de RAM

#### Scenario: Excesso de uma loja não afeta as outras
- **WHEN** uma loja usa toda a sua CPU
- **THEN** as demais lojas continuam respondendo normalmente

### Requirement: Cota de armazenamento por loja
Cada loja SHALL ter uma cota de 2 GB para os arquivos da loja, verificada periodicamente (intervalo de no máximo 5 minutos). Enquanto o uso estiver acima da cota, o envio de arquivos pela loja MUST ser recusado; quando o uso voltar para baixo da cota, o envio MUST voltar a ser aceito. O banco de dados não entra na cota.

#### Scenario: Uso abaixo da cota
- **WHEN** os arquivos da loja ocupam menos de 2 GB
- **THEN** o envio de arquivos pela loja é aceito

#### Scenario: Cota ultrapassada
- **WHEN** os arquivos da loja passam de 2 GB e ocorre a verificação seguinte
- **THEN** o envio de arquivos pela loja (vitrine e admin) é recusado e a loja continua navegável

#### Scenario: Espaço liberado
- **WHEN** o grupo apaga arquivos e o uso volta para baixo de 2 GB
- **THEN** na verificação seguinte o envio de arquivos volta a ser aceito

## MODIFIED Requirements

### Requirement: Geração de credenciais
O ambiente SHALL fornecer um comando que gera, uma única vez, senhas aleatórias de root do banco e, para cada grupo, senhas de banco, admin, Basic Auth e SSH, além da chave de host SSH, gravando-as para uso do Docker Compose e num arquivo `credenciais.txt` para o professor distribuir.

#### Scenario: Primeira geração
- **WHEN** o operador executa o comando de geração sem credenciais existentes
- **THEN** são criadas credenciais distintas para os 10 grupos e `credenciais.txt` lista, por grupo, a URL da loja, o usuário e a senha de Basic Auth, a URL, o usuário e a senha do admin, e o comando, o usuário e a senha de SSH

#### Scenario: Geração repetida não sobrescreve
- **WHEN** o operador executa o comando de geração e as credenciais já existem
- **THEN** nenhuma senha nem a chave de host SSH é alterada e o comando informa que as credenciais já existem

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
- **THEN** a loja do grupo4 volta ao estado recém-instalado, sem os dados cadastrados pelo grupo, e aceita as mesmas credenciais de Basic Auth, admin e SSH de antes

#### Scenario: Outros grupos intactos
- **WHEN** o reset do grupo4 é concluído
- **THEN** os dados e a disponibilidade das lojas dos demais grupos não são alterados

#### Scenario: Confirmação obrigatória
- **WHEN** o operador executa o reset sem confirmar a operação
- **THEN** nada é apagado

#### Scenario: Grupo inválido
- **WHEN** o operador executa o reset com um número fora de 1..10
- **THEN** o comando falha com mensagem de uso e nada é apagado
