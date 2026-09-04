# ADR 0001 - VPC própria em vez da default VPC

**Data:** 2026-09-04
**Status:** aceito

## Contexto

A instância precisa de rede com saída para a internet. A conta AWS já possui
uma default VPC (`172.31.0.0/16`), e usá-la eliminaria seis recursos do código.

## Decisão

Criar VPC própria: `10.0.0.0/16`, uma subnet pública `10.0.1.0/24`, Internet
Gateway, route table e associação.

## Razões

1. **Reprodutibilidade.** A default VPC não é criada pelo Terraform. Ela é
   provisionada pela AWS na criação da conta, varia entre contas e regiões, e
   pode ter sido alterada ou deletada. O requisito do desafio é que um
   `terraform apply` em ambiente limpo entregue o WordPress funcionando — e
   "ambiente limpo" inclui uma conta AWS diferente. Depender de um recurso que
   o código não cria quebra essa garantia.

2. **Defaults permissivos.** A default VPC vem com subnets em todas as AZs,
   todas com `map_public_ip_on_launch = true`, e um security group default que
   libera todo o tráfego entre seus membros. Nenhum desses defaults foi
   escolhido por este projeto.

3. **Blast radius explícito.** A conta é compartilhada com outro projeto
   (`aperia`). Uma VPC própria com CIDR distinto torna óbvio o que é deste
   ambiente e permite destruir tudo sem ambiguidade.

4. **CIDR sem sobreposição.** `10.0.0.0/16` não colide com `172.31.0.0/16`, o
   que mantém aberta a possibilidade de peering entre as duas no futuro.

## Consequências

- Seis recursos a mais no código e no state.
- O `apply` cria rede do zero, o que adiciona poucos segundos.
- A subnet usa `map_public_ip_on_launch = false`: a atribuição de IP público
  fica explícita na instância que precisa dele, e não herdada.

## Alternativa recusada

**Usar a default VPC com `data "aws_vpc" { default = true }`.** Menos código,
mas o ambiente deixa de ser descrito por completo no repositório. Em uma conta
onde a default VPC foi removida — prática comum em ambiente corporativo
endurecido — o `apply` falharia sem explicação óbvia.
