# ADR 0006 - Free tier: o que o requisito pede e o que a AWS oferece hoje

**Data:** 2026-09-04
**Status:** aceito

## Contexto

O requisito 2 do desafio é "instância dentro do free tier". A restrição
adicional imposta pelo responsável do projeto foi mais dura: nenhum custo.

Antes de escrever código, a premissa foi verificada contra a conta real em vez
de assumida.

## O que a verificação mostrou

```
$ aws freetier get-account-plan-state
accountPlanType: PAID
accountPlanStatus: ACTIVE
accountPlanRemainingCredits: USD 156.24

$ aws freetier get-free-tier-usage --query 'freeTierUsages[].freeTierType'
Always Free
Always Free
```

Nenhuma oferta do tipo `12 Month Free`. Somente `Always Free`.

```
$ aws pricing get-products --service-code AmazonEC2 \
    --filters instanceType=t2.micro operatingSystem=Linux tenancy=Shared \
              location="US East (N. Virginia)"
USD 0.0116 / Hrs
```

## A conclusão que isso força

**O free tier clássico de EC2 não existe em nenhuma conta AWS hoje.**

As 750 horas mensais de `t2.micro` por 12 meses só existiam em contas abertas
antes de 15 de julho de 2025, quando a AWS substituiu o modelo por créditos.
Qualquer conta anterior a essa data completou seus 12 meses em 15 de julho de
2026, no mais tardar. Hoje é 4 de setembro de 2026.

Isso não é limitação da conta usada. Abrir uma conta nova não resolveria: ela
cairia no modelo de créditos, exatamente como esta. É o calendário, não a conta.

## Decisão

1. **Usar `t2.micro`**, o tipo elegível ao free tier em `us-east-1`. É o que o
   requisito realmente verifica: que a escolha de tipo foi consciente e mínima,
   e não um `m5.xlarge`.
2. **Declarar o custo real** em vez de afirmar "é de graça". Um ciclo de cerca
   de 3 horas custa aproximadamente **USD 0,05**, abatido dos créditos
   existentes. Fatura final zero, mas é consumo de crédito, não free tier.
3. **Escrever os limites como validação de código**, e não como recomendação em
   texto.

## Os guardrails, e por que são código

| Guardrail | Implementação |
|---|---|
| `instance_type` aceita apenas `t2.micro` e `t3.micro` | `validation` em `variables.tf` — o Terraform recusa antes de falar com a AWS |
| `root_volume_size_gb` entre 8 e 30 GB | `validation` — 30 GB é o teto do free tier de EBS |
| Sem Elastic IP | Ausência deliberada. EIP **não associado** é cobrado sempre, inclusive com a instância parada. É a pegadinha de custo número um em laboratório |
| Sem NAT Gateway | ~USD 32/mês, e não existe subnet privada para servir |
| Sem RDS, sem ALB | ~USD 16/mês só do ALB |
| `monitoring = false` | Métricas de 1 minuto são cobradas; as de 5 minutos são gratuitas |
| SSM tier `Standard`, KMS gerenciada pela AWS | As versões pagas são `Advanced` e chave própria |

A diferença entre "escrevi no README para ter cuidado" e "o código não deixa
aplicar" é a diferença entre recomendação e controle. Um comentário pedindo
cuidado não impede erro; uma `validation` impede.

## O que deliberadamente não foi criado, mesmo sendo bom

**AWS Budget com alerta de gasto.** Seria o guardrail natural. Recusado porque
Budget é recurso de escopo de conta, e a conta é compartilhada com outro
projeto de outra pessoa — plantar alerta de orçamento no ambiente de terceiro
não é decisão que este projeto pode tomar.

No lugar dele: verificação de custo por leitura pura, antes e depois do ciclo,
com `aws ce get-cost-and-usage`. Não deixa rastro na conta.

## Consequência operacional

`terraform destroy` no fim do ciclo é parte do procedimento, não uma
recomendação. O README documenta o comando de conferência que confirma que
nenhuma instância do projeto continua de pé.
