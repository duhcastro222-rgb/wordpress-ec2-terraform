# ADR 0004 - State local em vez de backend remoto

**Data:** 2026-09-04
**Status:** aceito, com ressalva explícita

## Contexto

O state do Terraform pode ficar em arquivo local ou em backend remoto — no caso
da AWS, tipicamente S3 com lock. A conta usada já possui um bucket de state de
outro projeto (`aperia-tfstate-314068109572`).

## Decisão

State local, com `*.tfstate*` no `.gitignore`.

## Razões

1. **O requisito 1 do desafio é decisivo.** "Um `terraform apply` em ambiente
   limpo tem que entregar o WordPress acessível." Um backend remoto exige que o
   bucket S3 e a tabela de lock **já existam** antes do primeiro `init`. Isso
   cria um problema de ordem: ou se provisiona o bucket à mão — o que viola
   "sem console" — ou se cria um segundo projeto Terraform só para o bootstrap
   do backend, e então "um `apply`" passa a ser dois.

2. **Não encostar no projeto vizinho.** A conta é compartilhada. Reusar o
   bucket `aperia-tfstate` colocaria o state deste projeto dentro da área de
   outro. State local elimina qualquer chance de colisão de chave ou de lock.

3. **Sem colaboração concorrente.** Uma única pessoa aplica, num intervalo de
   horas. O problema que o lock remoto resolve — dois `apply` simultâneos
   corrompendo o state — não existe aqui.

## Consequências e a ressalva

**O state contém segredo em texto claro.** `random_password.db`,
`random_password.admin` e o valor dos parâmetros SSM estão gravados no arquivo,
legíveis com um editor de texto. Isso vale para qualquer state do Terraform,
remoto ou local — a diferença é onde o arquivo mora.

Consequências diretas:

- `*.tfstate*` está no `.gitignore`, e o Gitleaks no CI varre o histórico
  completo para garantir que nunca entrou.
- Nenhum output expõe valor de segredo, nem marcado como `sensitive`: o valor
  de output sensitive continua legível no state e recuperável com
  `terraform output -json`. Os outputs entregam o *comando* que busca o segredo.
- **Perder a máquina perde o state**, e o ambiente passa a ser órfão: recursos
  de pé sem nada que os gerencie. A mitigação neste projeto é a tag `Owner`, que
  permite localizar e remover tudo manualmente se necessário.
- Não há histórico de versões do state.

## O que seria feito em ambiente real

Backend S3 com versionamento habilitado, cifragem com KMS e lock nativo:

```hcl
terraform {
  backend "s3" {
    bucket       = "newchance-tfstate-<account-id>"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

O bucket viria de um projeto Terraform separado, aplicado uma única vez por
conta — o que é a resposta correta para o problema de ordem descrito acima, e
está fora do escopo desta entrega por prazo.
