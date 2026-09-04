# Convenções do Projeto

> Documento escrito **antes** da primeira linha de código e seguido sem exceção.
> Se algo no código divergir daqui, é bug de padronização — abra issue.

---

## 1. Nomes de recursos na AWS (a tag `Name` e nomes físicos)

**Formato:** `{project}-{environment}-{recurso}[-{qualificador}]`

- Sempre `kebab-case`, sempre minúsculo.
- `project` e `environment` vêm de variáveis, nunca hardcoded.
- O `recurso` usa o nome curto do serviço, não a sigla do Terraform.
- O `qualificador` só aparece quando existe mais de um do mesmo tipo.

| Recurso | Nome resultante |
|---|---|
| VPC | `newchance-dev-vpc` |
| Subnet pública | `newchance-dev-subnet-public-1a` |
| Internet Gateway | `newchance-dev-igw` |
| Route table | `newchance-dev-rtb-public` |
| Security group (web) | `newchance-dev-sg-web` |
| Instância EC2 | `newchance-dev-ec2` |
| IAM role | `newchance-dev-role-ec2` |
| IAM policy | `newchance-dev-policy-ssm-read` |
| Instance profile | `newchance-dev-profile-ec2` |
| Parâmetro SSM | `/newchance/dev/db/password` |

**Por quê:** prefixo comum permite localizar, filtrar por tag e destruir tudo do
projeto sem ambiguidade — importante nesta conta, que é compartilhada com outro
projeto (`aperia`).

---

## 2. Nomes locais no Terraform (o identificador no HCL)

**Formato:** `snake_case`, singular, **sem repetir o tipo do recurso**.

```hcl
resource "aws_vpc" "main" {}              # certo
resource "aws_vpc" "main_vpc" {}          # errado: "vpc" repetido
resource "aws_security_group" "web" {}    # certo
resource "aws_security_group" "sg_web" {} # errado: "sg" repetido
```

Referenciar fica `aws_vpc.main.id` e não `aws_vpc.main_vpc.id`. O tipo já está
na esquerda; repetir é ruído.

**Nomes locais reservados neste projeto:**
`main` (o recurso principal do módulo), `public` (subnet/rtb pública),
`web` (security group da instância), `wordpress` (a instância EC2),
`ec2` (role/profile/policy da instância).

---

## 3. Variáveis

- `snake_case`, sempre com `type` **e** `description`. Sem exceção.
- Boolean recebe prefixo `enable_`: `enable_ssh_access`.
- Coleção vai no plural: `allowed_ssh_cidrs`, `availability_zones`.
- Unidade explícita no nome quando houver: `root_volume_size_gb`, `swap_size_mb`.
- `validation` sempre que existir domínio conhecido (CIDR, tipo de instância).
- Segredo nunca tem `default`. Se é sensível, é `sensitive = true`.

## 4. Outputs

- `snake_case`, nomeado pelo que entrega, não pelo recurso de origem.
- `wordpress_url` (e não `aws_instance_public_ip_output`).
- Todo output que revele segredo leva `sensitive = true`.

---

## 5. Arquivos e diretórios

```
.
├── versions.tf      # required_version + required_providers (nada mais)
├── providers.tf     # bloco provider + default_tags
├── variables.tf     # todas as variáveis de entrada
├── main.tf          # composição: chamadas de módulo
├── outputs.tf       # todos os outputs
├── terraform.tfvars.example
├── docs/
│   ├── CONVENCOES.md
│   └── adr/         # uma decisão de arquitetura por arquivo
└── modules/
    ├── network/     # {main,variables,outputs,versions}.tf
    └── wordpress/
```

Módulo tem nome de **domínio, no singular** (`network`, não `networking`/`vpc`).
Todo módulo expõe exatamente os 4 arquivos acima — nunca `provider` dentro de
módulo (quem define provider é a raiz).

---

## 6. Tags obrigatórias

Aplicadas via `default_tags` no provider, portanto herdadas por todo recurso
que suporte tag. Nenhum recurso repete tag manualmente.

| Tag | Valor | Para quê |
|---|---|---|
| `Project` | `newchance` | Filtro e rateio de custo |
| `Environment` | `dev` | Separar ambiente |
| `ManagedBy` | `terraform` | Distinguir do que foi criado à mão |
| `Owner` | `duh.castro` | Conta compartilhada: identifica o responsável |

---

## 7. Branches

**Formato:** `{tipo}/{escopo-em-kebab-case}` — sempre criada a partir de `develop`.

| Tipo | Uso |
|---|---|
| `feature/` | Funcionalidade nova |
| `fix/` | Correção |
| `docs/` | Somente documentação |
| `ci/` | Pipeline e automação |
| `refactor/` | Reestruturação sem mudança de comportamento |

Regras: escopo com no máximo 4 palavras, sem número de issue no nome, sem nome
de pessoa. `main` e `develop` são branches base e nunca recebem push direto.

Fluxo: `feature/*` → PR → `develop` → PR → `main`.

---

## 8. Commits

**Formato:** `:emoji: tipo: descrição no imperativo`

Segue [iuricode/padroes-de-commits](https://github.com/iuricode/padroes-de-commits).
Emoji em *shortcode* (`:sparkles:`) e não em caractere Unicode — o GitHub
renderiza igual e evita problema de encoding entre Windows e Linux.

| Emoji | Tipo | Quando |
|---|---|---|
| `:tada:` | `init` | Commit inicial |
| `:sparkles:` | `feat` | Recurso novo |
| `:bug:` | `fix` | Correção de bug |
| `:books:` | `docs` | Documentação do projeto |
| `:bricks:` | `ci` | Pipeline / CI |
| `:wrench:` | `chore` | Configuração, tarefa administrativa |
| `:recycle:` | `refactor` | Reestruturação de código |
| `:lock:` | `security` | Melhoria de segurança |
| `:broom:` | `cleanup` | Remoção de código morto |

Descrição em **português, imperativo, minúscula, sem ponto final**, no máximo
~60 caracteres. Corpo do commit explica o *porquê*, nunca o *o quê* (o diff já
mostra o quê).

```
:sparkles: feat: adiciona modulo de rede          # certo
:sparkles: feat: Adicionado o módulo de rede.     # errado: particípio + ponto
feat: adiciona modulo de rede                     # errado: falta emoji
```

---

## 9. Código HCL

- `terraform fmt` obrigatório (validado no CI, o PR quebra se falhar).
- Ordem dentro do bloco: argumentos simples → blocos aninhados → `tags` → `lifecycle`.
- Ordem no arquivo: `data` → `resource` → `locals` quando local ao arquivo.
- Comentário explica **decisão**, não sintaxe. `# t2.micro: tipo elegivel ao
  free tier` é útil; `# cria a vpc` é ruído.
- Nada de `count` para condicional booleano quando `for_each` expressa melhor.
- Zero valor mágico: toda constante repetida vira `locals` ou variável.
