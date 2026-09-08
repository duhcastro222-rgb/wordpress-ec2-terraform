# newchance - WordPress em EC2 provisionado com Terraform

WordPress funcionando na AWS, provisionado inteiramente por Terraform. Um
`terraform apply` em ambiente limpo entrega o site acessível pelo browser, com
a instalação já concluída — sem console da AWS, sem SSH, sem assistente de
setup do WordPress.

---

## Sumário

- [O que é provisionado](#o-que-é-provisionado)
- [Reproduzir do zero](#reproduzir-do-zero)
- [Acessar o WordPress](#acessar-o-wordpress)
- [Destruir o ambiente](#destruir-o-ambiente)
- [Controles de segurança](#controles-de-segurança)
- [Por que o CI de segurança é a peça central](#por-que-o-ci-de-segurança-é-a-peça-central)
- [Decisões de arquitetura](#decisões-de-arquitetura)
- [Custo real](#custo-real)
- [Fora de escopo e por quê](#fora-de-escopo-e-por-quê)
- [Convenções](#convenções)

---

## O que é provisionado

```
                         Internet
                             |
                    [ Internet Gateway ]
                    newchance-dev-igw
                             |
   VPC 10.0.0.0/16  ---------+---------  newchance-dev-vpc
                             |
                    Subnet pública 10.0.1.0/24
                    newchance-dev-subnet-public-1a
                             |
                  +----------+----------+
                  |   EC2 t2.micro      |   newchance-dev-ec2
                  |   Amazon Linux 2023 |
                  |                     |
                  |   nginx  :80        |
                  |   php-fpm (socket)  |
                  |   MariaDB (local)   |
                  |   WordPress         |
                  |                     |
                  |   EBS gp3 8GB       |   cifrado em repouso
                  |   swap 2GB          |
                  +----------+----------+
                             |
                    role IAM (menor privilégio)
                             |
              +--------------+--------------+
              |                             |
     SSM Parameter Store            SSM Session Manager
     /newchance/dev/db/password     acesso administrativo
     /newchance/dev/wordpress/...   sem chave e sem porta
     (SecureString, KMS)
```

**24 recursos**, distribuídos em dois módulos:

| Módulo | Recursos |
|---|---|
| `modules/network` | VPC, subnet pública, Internet Gateway, route table, associação, security group default esvaziado |
| `modules/wordpress` | Security group + 4 regras, role IAM + policy + instance profile, 2 parâmetros SSM, 2 senhas aleatórias, key pair, instância EC2 |

---

## Reproduzir do zero

### Pré-requisitos

| Ferramenta | Versão usada | Verificar |
|---|---|---|
| Terraform | 1.15.8 | `terraform version` |
| AWS CLI | 2.36.21 | `aws --version` |
| Git | 2.53 | `git --version` |

E uma credencial da AWS configurada com permissão para criar VPC, EC2, IAM e
parâmetros no SSM:

```bash
aws configure
aws sts get-caller-identity   # confirma que a credencial funciona
```

### 1. Clonar

```bash
git clone https://github.com/duhcastro222-rgb/wordpress-ec2-terraform.git
cd wordpress-ec2-terraform
```

### 2. Gerar um par de chaves SSH fora do repositório

O diretório do repositório nunca deve conter chave privada. Gere em `~/.ssh`:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/newchance -N "" -C newchance
```

Este passo é opcional. Sem chave, nenhum key pair é criado e o acesso
administrativo acontece por SSM Session Manager, que não usa chave nem porta.

### 3. Criar o `terraform.tfvars`

```bash
cp terraform.tfvars.example terraform.tfvars
```

Descubra seu IP público e edite o arquivo:

```bash
curl https://checkip.amazonaws.com
```

```hcl
allowed_ssh_cidrs = ["SEU.IP.AQUI/32"]
ssh_public_key    = "conteúdo de ~/.ssh/newchance.pub"
```

`terraform.tfvars` está no `.gitignore` e nunca deve ser versionado.

Se `allowed_ssh_cidrs` ficar vazio, **nenhuma regra na porta 22 é criada** — o
comportamento padrão é fail-closed. A validação da variável rejeita `0.0.0.0/0`.

### 4. Aplicar

```bash
terraform init
terraform plan
terraform apply
```

O `apply` leva cerca de 40 segundos. O bootstrap dentro da instância leva mais
2 a 3 minutos: instalar pacotes, configurar MariaDB e PHP-FPM, baixar o
WordPress e concluir a instalação.

### 5. Verificar

```bash
curl -o /dev/null -w "%{http_code}\n" "$(terraform output -raw wordpress_url)"
```

Quando responder `200`, abra a URL no browser.

Enquanto responder `000`, o bootstrap ainda está em curso. Para acompanhar de
dentro da instância, sem SSH:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
sudo tail -f /var/log/wordpress-bootstrap.log
```

O script grava o resultado final em `/var/log/wordpress-bootstrap-done`, com
`OK` ou `FALHA` e o código HTTP que ele mesmo verificou.

---

## Acessar o WordPress

```bash
terraform output wordpress_url         # o site
terraform output wordpress_admin_url   # o painel
terraform output wordpress_admin_user  # o usuário
```

A senha do administrador **não é exposta como output**. Nem mesmo marcada como
`sensitive`: o valor de um output sensitive continua gravado em texto claro no
state e é recuperável com `terraform output -json`. Em vez do valor, o output
entrega o comando que busca o segredo com a credencial de quem executa:

```bash
eval "$(terraform output -raw comando_senha_admin)"
```

Ou diretamente:

```bash
aws ssm get-parameter \
  --name /newchance/dev/wordpress/admin-password \
  --with-decryption --region us-east-1 \
  --query Parameter.Value --output text
```

> **Reproduzindo no Windows com Git Bash:** exporte `MSYS_NO_PATHCONV=1` antes
> de qualquer comando que receba um caminho de parâmetro do SSM. O Git Bash
> converte argumentos que se parecem com caminho Unix em caminho Windows, e
> `/newchance/dev/db/password` chega na AWS como
> `C:/Program Files/Git/newchance/dev/db/password`. O erro devolvido é
> `ParameterNotFound`, que aponta para o lugar errado e custa tempo de
> diagnóstico.
>
> ```bash
> export MSYS_NO_PATHCONV=1
> ```
>
> No PowerShell e em Linux o problema não existe.

Para confirmar que o segredo está de fato cifrado em repouso, peça o parâmetro
**sem** `--with-decryption`:

```bash
aws ssm get-parameter --name /newchance/dev/wordpress/admin-password \
  --region us-east-1 --query Parameter.Value --output text
# AQICAHijJhmF0BRPRft9e1VOBLoYUQrNPDN0BFYMW4Wxub7u7QHfqVNEaM+V...
```

O retorno é o blob cifrado pela chave KMS, não a senha.

### Acesso administrativo à instância

Dois caminhos, em ordem de preferência:

```bash
# 1. SSM Session Manager: sem chave, sem porta aberta, com registro no CloudTrail
aws ssm start-session --target "$(terraform output -raw instance_id)"

# 2. SSH, restrito ao IP declarado em allowed_ssh_cidrs
ssh -i ~/.ssh/newchance ec2-user@"$(terraform output -raw instance_public_ip)"
```

---

## Destruir o ambiente

```bash
terraform destroy
```

Depois, confirme que nada sobrou gerando custo:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=newchance" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
```

Saída vazia significa que não há instância deste projeto de pé.

---

## Controles de segurança

Além do que o desafio pedia. Todos de custo zero.

### Credenciais e segredos

| Controle | O que mitiga |
|---|---|
| Senhas geradas pelo Terraform e gravadas no **SSM Parameter Store como SecureString** | O `user_data` é legível por qualquer processo local via IMDS e por qualquer principal com `ec2:DescribeInstanceAttribute`. Senha em `user_data` é o erro mais comum neste tipo de provisionamento |
| A instância lê o segredo **em tempo de boot**, pela role IAM | O segredo não trafega no código, nem no plan, nem no template |
| Policy IAM **sem curinga**: `ssm:GetParameter` nos dois ARNs exatos, `kms:Decrypt` na chave do SSM com condição `kms:ViaService` | Instância comprometida não lê segredo de outro projeto na mesma conta AWS |
| Senha de 40 caracteres alfanuméricos | Comprimento em vez de composição: ~238 bits de entropia. Excluir símbolos também elimina uma classe de bug de escape no script de bootstrap, que roda sem depuração interativa |
| Chave privada SSH **nunca passa pelo Terraform** | Só a parte pública entra como variável, portanto a privada não existe no state |
| `set -x` **proibido** por comentário no script de bootstrap | Modo verboso imprime o valor de toda variável expandida, incluindo a senha lida do SSM, e o log do cloud-init permanece legível na instância |

### Rede

| Controle | O que mitiga |
|---|---|
| Porta 22 restrita a um `/32`, com `default = []` (fail-closed) e validação que rejeita `0.0.0.0/0` | Um controle que depende de disciplina não é controle. Aqui o Terraform recusa antes de falar com a AWS |
| **Egress porta a porta**: apenas 443 para a internet, 53 restrito ao CIDR da VPC | Uma regra de saída liberando todo protocolo para qualquer destino dá ao atacante canal de comando e controle e exfiltração livre. Restringir a saída não impede a invasão, encurta o que vem depois |
| `map_public_ip_on_launch = false` na subnet | Com `true`, toda instância criada na subnet herda IP público, inclusive uma que não deveria. A atribuição fica explícita na instância |
| **Security group default da VPC adotado e esvaziado** | Toda VPC nasce com um SG default que libera tráfego entre seus membros. Recurso criado sem SG explícito passa a cair num grupo que não permite nada |

### Instância

| Controle | O que mitiga |
|---|---|
| **IMDSv2 obrigatório** (`http_tokens = "required"`), hop limit 1 | Com IMDSv1, um `GET` simples ao endpoint de metadados devolve a credencial temporária da role: qualquer SSRF na aplicação vira roubo de credencial da conta AWS. É o vetor do caso Capital One |
| EBS **cifrado em repouso** | Custo zero com chave gerenciada pela AWS |
| Usuário do banco dedicado, restrito a `localhost`, com privilégio apenas no próprio banco | SQL injection na aplicação não herda privilégio de `root` do MariaDB |
| Usuários anônimos e banco `test` removidos do MariaDB | Defaults inseguros da instalação |
| **SSM Session Manager** como acesso administrativo primário | Sem chave para vazar, sem porta para varrer, com registro no CloudTrail. A porta 22 continua restrita como o desafio exige, mas o caminho bom fica demonstrado ao lado |

### WordPress e nginx

| Controle | O que mitiga |
|---|---|
| `DISALLOW_FILE_EDIT` | Com o editor de temas ativo, um único cookie de admin roubado permite escrever PHP arbitrário no servidor: comprometimento de conta vira execução remota de código |
| `xmlrpc.php` com `return 444` | `system.multicall` aceita centenas de tentativas de senha em uma requisição, e o pingback serve de amplificador de DDoS |
| PHP negado em `wp-content/uploads` e em `wp-includes` | Caminho mais curto de upload malicioso para webshell |
| **Ordem dos blocos `location`** tratada como controle, com a razão em comentário | Entre `location` com regex, o nginx aplica o primeiro que casa. Uma negação declarada depois do bloco genérico `~ \.php$` é inalcançável — ver [problemas encontrados](#problemas-encontrados-na-execução-real) |
| `server_tokens off` e `expose_php = Off` | Remove o banner de versão que scanner automatizado usa para escolher exploit sem tentativa e erro |
| `display_errors = Off` | Stack trace revela caminho absoluto, versão de biblioteca e às vezes credencial |
| `wp-config.php` em `640` | Guarda a senha do banco em texto claro; com `644` qualquer usuário local lê |
| Salts únicos gerados na instalação | Salt reaproveitado entre instalações permite forjar cookie de sessão válido |
| Usuário admin não pode ser `admin`, `root`, `administrator` ou `wordpress` (validação) | São os primeiros nomes tentados por qualquer ataque de força bruta |
| `DISALLOW_UNFILTERED_HTML` | Fecha um caminho comum de XSS armazenado por usuário não administrador |

### Cadeia de suprimentos e pipeline

| Controle | O que mitiga |
|---|---|
| `.terraform.lock.hcl` **versionado** | Fixa o hash criptográfico de cada provider. Sem ele, um `terraform init` em outra máquina pode resolver versão diferente, e potencialmente comprometida, sem aviso |
| **Actions do GitHub fixadas por SHA de commit**, não por tag | Tag no Git é mutável: quem controla o repositório da action pode apontar `v5` para outro commit e a pipeline executa código diferente sem que nada mude aqui. Foi o vetor do comprometimento de `tj-actions/changed-files` em 2025 |
| `permissions: contents: read` no workflow | O `GITHUB_TOKEN` padrão pode ter escopo bem mais amplo. Se um passo for comprometido, o token que ele carrega é o limite do dano |
| Pipeline **sem nenhuma credencial da AWS** | Toda checagem é estática (`init -backend=false`, `validate`, análise de HCL). Pipeline que não precisa de segredo não pode vazar segredo |
| **Gitleaks com `fetch-depth: 0`** | Varre o histórico completo, não só a árvore atual. Segredo removido num commit posterior continua recuperável — `git rm` de uma chave não a desvaza |
| `.trivyignore` com **política de justificativa obrigatória** | Arquivo de ignore sem explicação transforma alerta legítimo em silêncio permanente. Risco aceito é decisão; risco silenciado é dívida |

### Três camadas independentes para "nenhuma credencial versionada"

O requisito 3 do desafio deixa de ser promessa e passa a ser controle verificado:

1. **`.gitignore`** — impede o commit acidental de `*.tfstate`, `*.tfvars`, `*.pem`, `.env`
2. **GitHub secret scanning + push protection** — bloqueia o push no servidor
3. **Gitleaks no CI** — falha o Pull Request se algo passou pelas duas primeiras

---

## Por que o CI de segurança é a peça central

Todo controle listado acima tem o mesmo ponto fraco: ele depende de alguém ter
escrito o código certo, e de ninguém apagar isso depois. O CI de segurança é o
que transforma intenção em garantia — e é a diferença entre um repositório que
*diz* ser seguro e um que *prova* a cada Pull Request.

### O problema que ele resolve

Sem pipeline, a segurança da infraestrutura depende de três coisas frágeis:

| Sem CI | Com CI |
|---|---|
| O revisor precisa lembrar de olhar cifragem, IMDSv2, egress e curinga de IAM em cada PR | A ferramenta olha os quatro, sempre, em segundos |
| Um segredo commitado só é descoberto quando alguém o encontra — ou quando alguém o usa | Falha o PR antes do merge |
| Uma regra de segurança removida por engano passa como "refatoração" | O achado reaparece imediatamente |
| A qualidade da revisão varia com o cansaço, o prazo e a experiência de quem revisa | Não varia |

Revisão humana continua indispensável, mas para o que exige julgamento. Para
"este bucket está cifrado?" e "esta porta está aberta para o mundo?", máquina
não esquece e não tem sexta-feira à noite.

### O que a pipeline deste projeto faz

Três jobs, em todo PR para `develop` e `main`:

| Job | Ferramenta | O que verifica |
|---|---|---|
| `terraform` | Terraform | `fmt -check`, `init -backend=false`, `validate` |
| `iac-misconfig` | **Trivy** | Configuração insegura no HCL: recurso sem cifragem, porta aberta ao mundo, IMDSv1 permitido, IAM com curinga |
| `secrets` | **Gitleaks** | Credencial versionada em **qualquer commit do histórico** |

### As decisões que fazem a pipeline ser segura, e não só útil

Uma pipeline de segurança mal configurada é ela própria um vetor de ataque —
ela roda código, tem token e enxerga o repositório inteiro.

**Nenhuma credencial da AWS na pipeline.** Toda checagem é estática: o `init`
roda com `-backend=false` e o `validate` não fala com a API da AWS. Pipeline que
não precisa de segredo não pode vazar segredo — e não há chave nem OIDC para
gerenciar, rotacionar ou perder.

**`permissions: contents: read`.** O `GITHUB_TOKEN` padrão pode ter escopo bem
mais amplo, inclusive escrita. Se um passo da pipeline for comprometido, o token
que ele carrega é o limite exato do dano.

**Toda action fixada por SHA de commit, nunca por tag.** Tag no Git é mutável:
quem controla o repositório de uma action pode apontar `v5` para outro commit, e
a pipeline passa a executar código diferente sem que uma única linha mude neste
repositório. Foi exatamente o vetor do comprometimento de
`tj-actions/changed-files` em 2025, que expôs segredos de milhares de
repositórios. SHA é imutável.

```yaml
uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
```

O comentário registra a versão para que a atualização continue legível.

**Gitleaks com `fetch-depth: 0`.** Varre o histórico completo, não a árvore
atual. Segredo removido num commit posterior continua recuperável no histórico —
e continua comprometido. Dar `git rm` numa chave não a desvaza.

**Trivy e Gitleaks se complementam, não se sobrepõem.** O Trivy analisa
configuração insegura na infraestrutura; o Gitleaks procura credencial
versionada. O Trivy também varre segredo, mas só sobre a árvore de arquivos —
não sobre o histórico do git, que é justamente onde a evidência fica.

**`.trivyignore` com justificativa obrigatória.** Nada entra no arquivo de
exceções sem a razão escrita ao lado e um critério de reavaliação. Arquivo de
ignore sem explicação é pior que nenhum: transforma um alerta legítimo em
silêncio permanente que ninguém sabe por que existe. **Risco aceito é uma
decisão; risco silenciado é uma dívida.**

### O ciclo funcionando de verdade

O valor da pipeline não é passar — é apontar. Neste projeto o Trivy reportou
três achados de egress irrestrito. A revisão que ele provocou mostrou que
**duas daquelas regras eram desnecessárias e foram removidas do código**
(`80/tcp`, que nunca foi usado porque todo o bootstrap é HTTPS, e `123/udp`, que
nunca teve efeito porque o Amazon Time Sync responde em endereço link-local que
Security Group não filtra). A terceira, `443/tcp`, é inevitável e ficou
declarada como exceção justificada.

Resultado: a superfície de saída caiu de três regras abertas para uma, com a
razão registrada. Um alerta de ferramenta serve para provocar revisão, não para
ser silenciado.

### Três camadas independentes para o requisito "nenhuma credencial versionada"

```
1. .gitignore                          impede o commit acidental
2. GitHub secret scanning + push       BLOQUEIA o push, no servidor
   protection
3. Gitleaks no CI                      FALHA o Pull Request se passou pelas
                                       duas primeiras
```

As três são independentes e nenhuma depende de disciplina humana. É isso que
separa um controle de uma boa intenção.

---

## Decisões de arquitetura

Detalhe em [`docs/adr/`](docs/adr/). Resumo:

| Decisão | Escolha | Razão principal |
|---|---|---|
| Rede | **VPC própria**, não a default | A default VPC não é criada pelo Terraform, varia entre contas e não é reproduzível em ambiente limpo — quebraria o requisito de automação total |
| Banco | **MariaDB local**, não RDS | Free tier real e `apply` em segundos. RDS leva 10 a 15 minutos e sai do free tier após 12 meses. Para um blog single-node é complexidade sem retorno |
| Módulos | **Dois**: `network` e `wordpress` | Separa o que quase nunca muda do que muda sempre. Mais que isso, com um único recurso de compute, é abstração vazia |
| State | **Local** | Backend remoto exigiria provisionar S3 e DynamoDB antes do primeiro `apply`, o que quebra "um `terraform apply` em ambiente limpo" |
| AMI | `data source`, sem ID fixado | ID de AMI é regional e envelhece |
| Bootstrap | `user_data` com cloud-init | Único caminho que atende "sem console e sem SSH" |
| Instalação | **WP-CLI**, não o assistente web | O assistente exigiria um passo manual no browser, violando a automação total |
| IP público | **Auto-atribuído**, sem Elastic IP | EIP não associado é cobrado sempre, inclusive com a instância parada. É a pegadinha de custo número um neste tipo de laboratório |

---

## Custo real

O desafio pede free tier. A resposta honesta exige uma correção de premissa.

**O free tier clássico de EC2 não existe mais em nenhuma conta hoje.** As 750
horas mensais de `t2.micro` por 12 meses só existiam em contas abertas antes de
15 de julho de 2025, quando a AWS trocou o modelo por créditos. Qualquer conta
anterior a essa data completou seus 12 meses em 15 de julho de 2026, no mais
tardar. Não é limitação de uma conta específica, é o calendário.

Verificado na conta usada:

```
$ aws freetier get-account-plan-state
accountPlanType: PAID          accountPlanStatus: ACTIVE
accountPlanRemainingCredits: USD 156.24

$ aws freetier get-free-tier-usage --query 'freeTierUsages[].freeTierType'
Always Free        <- nenhuma oferta "12 Month Free"

$ aws pricing get-products ... t2.micro ... Linux ... us-east-1
USD 0.0116 / hora
```

Custo de um ciclo completo de cerca de 3 horas — provisionar, validar, tirar
evidência e destruir:

| Item | Cálculo | Custo |
|---|---|---|
| EC2 `t2.micro` | USD 0,0116/h x 3h | 0,0348 |
| IPv4 público em uso | USD 0,005/h x 3h | 0,0150 |
| EBS gp3 8 GB | USD 0,64/mês / 730h x 3h | 0,0026 |
| VPC, IGW, security group, route table, IAM, SSM Standard | — | 0,00 |
| Tráfego de saída | primeiros 100 GB/mês são *always free* | 0,00 |
| **Total** | | **≈ USD 0,05** |

Abatido dos créditos existentes. Fatura final: zero. Mas é consumo de crédito,
não free tier — e a diferença importa quando alguém pergunta.

### Guardrails de custo escritos como código

| Guardrail | Onde |
|---|---|
| `instance_type` aceita **apenas** `t2.micro` e `t3.micro` | `validation` em `variables.tf` |
| `root_volume_size_gb` limitado a 30 GB, teto do free tier de EBS | `validation` em `variables.tf` |
| Sem Elastic IP, sem NAT Gateway, sem RDS, sem ALB | ausência deliberada no código |
| Parâmetros SSM em tier `Standard`, chaves KMS gerenciadas pela AWS | `modules/wordpress/main.tf` |
| `monitoring = false` — métricas de 1 minuto são cobradas | `modules/wordpress/main.tf` |

A diferença entre "escrevi no README para ter cuidado" e "o código não deixa" é
a diferença entre recomendação e controle.

---

## Fora de escopo e por quê

| Não implementado | Por quê | Como seria |
|---|---|---|
| **HTTPS / TLS** | Sem domínio próprio não existe certificado válido. Certificado autoassinado entregaria aviso de segurança no browser, que é pior que HTTP claro para uma evidência | ALB + ACM, ou Caddy com DNS e Let's Encrypt |
| **Backend remoto de state** | Exigiria provisionar S3 e DynamoDB antes do primeiro `apply` | S3 com versionamento e cifragem + lock nativo |
| **RDS** | Fora do free tier após 12 meses, e 10 a 15 minutos de provisionamento | `db.t4g.micro` Multi-AZ em subnets privadas |
| **Auto Scaling e ALB** | ALB custa cerca de USD 16/mês. Sem requisito de disponibilidade, é custo sem retorno | ASG mínimo 2, ALB, EFS para `wp-content` |
| **VPC Flow Logs** | Ingestão no CloudWatch Logs é cobrada além de 5 GB. Excluído pela restrição de custo, não por falta de valor | Flow logs para S3 com retenção curta |
| **GuardDuty e AWS Config** | Cobrados após o período de avaliação | Habilitados por padrão em conta de produção |
| **Backup** | Sem AWS Backup e sem snapshot agendado | Data Lifecycle Manager com snapshot diário |
| **WAF** | Custo por regra e por requisição | AWS WAF no ALB com regras gerenciadas |

Nada disso é acidental. Cada item foi avaliado e recusado por uma razão
específica — custo, prazo ou ausência de requisito.

---

## Convenções

Padrão de nomenclatura de recursos, variáveis, arquivos, módulos, tags,
branches e commits: [`docs/CONVENCOES.md`](docs/CONVENCOES.md).

O padrão foi escrito **antes** da primeira linha de HCL.

### Nomes de recurso

Formato `{project}-{environment}-{recurso}`, em `kebab-case`. `project` e
`environment` vêm de variável e nunca são escritos à mão:

```
newchance-dev-vpc          newchance-dev-sg-web
newchance-dev-subnet-public-1a   newchance-dev-role-ec2
newchance-dev-igw          newchance-dev-ec2
newchance-dev-rtb-public   /newchance/dev/db/password
```

Os 20 nomes de recurso, o caminho dos segredos no SSM e a tag `Project` derivam
todos da mesma origem — o `local.name_prefix` no `main.tf`. Nenhum nome é
duplicado no código, portanto nenhum pode divergir dos outros.

### Commits

`tipo: descrição no imperativo`, seguindo
[Conventional Commits](https://www.conventionalcommits.org), com o conjunto de
tipos de [iuricode/padroes-de-commits](https://github.com/iuricode/padroes-de-commits)
como referência de vocabulário.

```
feat: adiciona modulo de rede
fix: corrige ordem dos blocos location do nginx
ci: adiciona pipeline de analise estatica de seguranca
docs: adiciona readme de reproducao e registros de decisao
```

Descrição em português, imperativo, minúscula, sem ponto final. O corpo do
commit explica o *porquê*; o diff já mostra o *quê*.

### Branches

```
main                     protegida: PR obrigatório, 1 aprovação,
                         sem force-push, sem deleção
develop                  branch de integração
<tipo>/<escopo-kebab>    feature/, fix/, ci/, docs/, refactor/
```

Fluxo: `<tipo>/<escopo>` -> Pull Request -> `develop` -> Pull Request -> `main`.
