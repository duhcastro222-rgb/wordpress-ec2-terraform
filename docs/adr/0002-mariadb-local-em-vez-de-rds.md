# ADR 0002 - MariaDB local na instância em vez de RDS

**Data:** 2026-09-04
**Status:** aceito

## Contexto

O WordPress exige MySQL ou MariaDB. As opções são instalar o banco na própria
EC2 ou provisionar um RDS gerenciado.

## Decisão

MariaDB 10.5 instalado na própria instância, com usuário dedicado restrito a
`localhost`.

## Razões

1. **Custo.** A restrição do projeto é custo zero. O free tier de RDS é uma
   oferta de 12 meses, e a conta usada está fora dessa janela — o modelo de
   free tier mudou em 15 de julho de 2025 e passou a ser baseado em créditos.
   Um `db.t4g.micro` custaria por hora, e Multi-AZ dobraria isso.

2. **Prazo.** RDS leva de 10 a 15 minutos para ficar disponível. Isso
   multiplica o tempo de cada ciclo de teste. Ao longo desta entrega foram
   feitos quatro ciclos de `apply` completos para corrigir falhas de bootstrap;
   com RDS no caminho, o custo em tempo seria proibitivo.

3. **YAGNI.** Um blog single-node sem requisito de disponibilidade não se
   beneficia de failover automático, réplica de leitura ou backup gerenciado.
   RDS resolve problemas que este projeto não tem.

4. **Superfície de rede menor.** Banco em `localhost` não escuta na rede. Não
   há subnet de banco, não há security group de banco, não há credencial
   trafegando entre hosts.

## Consequências

- **Sem alta disponibilidade.** Perder a instância perde o banco.
- **Sem backup gerenciado.** Nenhum snapshot automático está configurado.
- **Sem escala independente.** Aplicação e banco competem pela mesma RAM de
  1 GB, o que exigiu 2 GB de swap e reduzir `pm.max_children` do PHP-FPM de 50
  para 5.
- Dados são efêmeros por design: o ambiente é criado, validado e destruído.

Essas consequências são aceitáveis porque o objetivo é demonstrar
provisionamento automatizado, não operar um blog em produção.

## Alternativa recusada

**RDS `db.t4g.micro` em subnets privadas.** É a arquitetura correta para
produção e seria a primeira mudança a fazer se este ambiente virasse real. O
`modules/wordpress` já recebe a senha do banco via SSM Parameter Store, portanto
a migração trocaria `localhost` pelo endpoint do RDS sem mexer no fluxo de
segredo.
