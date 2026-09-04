# ADR 0005 - Segredos no SSM Parameter Store, nunca no user_data

**Data:** 2026-09-04
**Status:** aceito

## Contexto

O bootstrap precisa da senha do banco e da senha do administrador do WordPress.
O caminho mais curto é interpolar as senhas diretamente no `user_data`, que é o
que a maioria dos exemplos de WordPress em Terraform faz.

## Decisão

O Terraform gera as senhas com `random_password`, grava no SSM Parameter Store
como `SecureString`, e passa ao `user_data` apenas o **caminho** do parâmetro. A
instância busca o valor em tempo de boot usando sua role IAM.

## Razão principal: user_data não é secreto

O `user_data` é recuperável por dois caminhos independentes:

1. **De dentro da instância**, por qualquer processo, sem privilégio nenhum:

   ```bash
   TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
     -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
   curl -H "X-aws-ec2-metadata-token: $TOKEN" \
     http://169.254.169.254/latest/user-data
   ```

   Isso significa que o processo do PHP-FPM, um plugin comprometido do
   WordPress, ou qualquer coisa que consiga executar código na instância lê a
   senha sem esforço.

2. **De fora**, por qualquer principal com `ec2:DescribeInstanceAttribute`:

   ```bash
   aws ec2 describe-instance-attribute --attribute userData --instance-id i-...
   ```

   Essa permissão é frequentemente concedida em papéis de leitura ampla, do tipo
   `ReadOnlyAccess`, que muita gente considera inofensivo.

## Como fica no lugar disso

```
Terraform: random_password  ->  SSM Parameter Store (SecureString, chave aws/ssm)
                                        ^
                                        | ssm:GetParameter + kms:Decrypt
                                        | (role da instância, no boot)
                                        |
user_data: apenas "/newchance/dev/db/password"  ->  instância
```

A policy da role não tem curinga:

- `ssm:GetParameter` e `ssm:GetParameters` **nos dois ARNs exatos**
- `kms:Decrypt` **na chave que cifra o parâmetro**, com condição
  `kms:ViaService = ssm.us-east-1.amazonaws.com`

O efeito da condição: mesmo tendo `kms:Decrypt`, a instância não consegue usar
aquela chave para decifrar dado de outro serviço.

## Decisões acessórias

- **Senha de 40 caracteres alfanuméricos, sem símbolos.** Comprimento em vez de
  composição: cerca de 238 bits de entropia, muito acima de qualquer exigência
  prática. Excluir símbolos também elimina uma classe inteira de bug de escape
  num script que roda sem depuração interativa.
- **Tier `Standard`.** Gratuito até 10.000 parâmetros. `Advanced` é cobrado.
- **`set -x` proibido no script**, com comentário explicando a razão. Durante o
  diagnóstico desta entrega o modo verboso imprimiu a senha em texto claro na
  saída de um comando SSM, e a senha teve de ser rotacionada. O comentário
  existe para que o próximo a depurar não repita.

## Consequências

- A instância depende da role IAM estar anexada e propagada no boot. O script
  tem laço de espera de até 150 segundos para a credencial ficar disponível, em
  vez de falhar na primeira tentativa.
- O segredo ainda existe em texto claro no state do Terraform — ver
  [ADR 0004](0004-state-local-em-vez-de-backend-remoto.md).
- Rotacionar a senha é um comando:
  `terraform apply -replace='module.wordpress.random_password.db'`.

## Alternativa recusada

**Interpolar a senha no `user_data`.** Menos recursos, menos IAM, menos código.
Recusado porque coloca a credencial do banco em dois lugares legíveis por quem
não deveria ler, e porque é exatamente o tipo de atalho que um revisor de
segurança procura primeiro.
