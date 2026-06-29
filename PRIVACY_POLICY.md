# Politica de Privacidade do EcoScan

**Vigencia:** 25 de junho de 2026

O EcoScan identifica plantas a partir de fotografias enviadas pelo aplicativo.
Esta politica explica quais dados sao tratados, por que sao necessarios e quais
controles estao disponiveis ao usuario.

## Dados tratados

O EcoScan pode tratar:

- nome e endereco de email informados no cadastro;
- senha armazenada somente como hash criptografico;
- fotografias de plantas enviadas para identificacao;
- resultado da identificacao, nivel de confianca, data e vinculo com o usuario;
- registros adicionados ao historico ou a biblioteca;
- tokens de sessao armazenados de forma segura no dispositivo;
- tokens temporarios e de uso unico para recuperacao de senha;
- dados tecnicos essenciais de requisicoes e falhas do servico.

O aplicativo solicita acesso a camera somente para capturar fotografias de
plantas. Ele nao solicita localizacao, contatos ou microfone.

## Finalidades

Os dados sao utilizados para:

- autenticar e manter a sessao do usuario;
- identificar plantas e apresentar a confianca do modelo;
- manter historico e biblioteca vinculados a conta;
- permitir edicao de perfil, recuperacao de senha e exclusao de registros;
- proteger, diagnosticar e manter o servico.

## Armazenamento e seguranca

Os dados da conta, metadados e imagens salvas sao armazenados no PostgreSQL da
API. Senhas nao sao armazenadas em texto puro. A comunicacao de producao usa
HTTPS, e os tokens de sessao ficam no armazenamento seguro do Android.

O acesso operacional ao banco e aos backups deve ser restrito. Backups contem
os mesmos tipos de dados do banco e devem permanecer criptografados ou em
armazenamento com controle de acesso.

## Retencao e exclusao

O usuario pode remover identificacoes ou excluir definitivamente a conta pelo
aplicativo. A confirmacao e exigida antes da exclusao. A exclusao da conta
remove historico, biblioteca, imagens e tokens vinculados.

Identificacoes fora da biblioteca podem ser removidas pela rotina de retencao
apos 90 dias. Itens mantidos na biblioteca permanecem ate serem removidos pelo
usuario ou ate o encerramento do servico. Tokens de recuperacao expirados sao
eliminados por rotina de manutencao.

Copias em backups podem permanecer por um periodo operacional limitado antes
de serem substituidas ou excluidas.

## Compartilhamento

Os dados nao sao vendidos. Eles podem ser processados por fornecedores
necessarios para operar o servico, como hospedagem, banco de dados, entrega de
email e monitoramento tecnico, sujeitos aos respectivos contratos e medidas de
seguranca.

## Direitos do usuario

O usuario pode atualizar nome e email e excluir registros pelo aplicativo.
Solicitacoes sobre acesso, correcao, exclusao da conta ou outros direitos de
privacidade podem ser feitas pelo canal de contato abaixo.

As instrucoes publicas para exclusao estao em:

https://github.com/Pulves/ecoScan/blob/front_app/ACCOUNT_DELETION.md

## Menores de idade

O EcoScan nao e direcionado intencionalmente a criancas sem supervisao de seus
responsaveis. Caso dados de uma crianca tenham sido enviados indevidamente,
solicite a remocao pelo canal de contato.

## Alteracoes desta politica

Esta politica pode ser atualizada quando houver mudancas no aplicativo ou nas
exigencias legais. A data de vigencia sera atualizada no inicio do documento.

## Contato

Duvidas e solicitacoes de privacidade podem ser registradas em:

https://github.com/Pulves/ecoScan/issues
