# ==============================================================================
# Identificacao e nomenclatura
# ==============================================================================

variable "aws_region" {
  description = "Regiao AWS onde o ambiente sera provisionado."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto. Compoe o prefixo de todo nome de recurso."
  type        = string
  default     = "wordpress"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name deve ser kebab-case minusculo, de 2 a 20 caracteres."
  }
}

variable "environment" {
  description = "Ambiente. Compoe o prefixo de todo nome de recurso."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "hml", "prd"], var.environment)
    error_message = "environment deve ser um de: dev, hml, prd."
  }
}

variable "owner" {
  description = "Responsavel pelos recursos, usado na tag Owner. A conta AWS e compartilhada com outro projeto, portanto esta tag e o que separa este ambiente dos demais."
  type        = string
  default     = "duh.castro"
}

# ==============================================================================
# Rede
# ==============================================================================

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC. Nao deve sobrepor a default VPC da conta (172.31.0.0/16)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr deve ser um bloco CIDR valido, por exemplo 10.0.0.0/16."
  }
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR da subnet publica. Deve estar contido em vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr deve ser um bloco CIDR valido, por exemplo 10.0.1.0/24."
  }
}

# ==============================================================================
# Computacao
# ==============================================================================

variable "instance_type" {
  description = "Tipo da instancia EC2. A validacao restringe aos tipos elegiveis ao free tier, o que impede subir acidentalmente uma instancia paga."
  type        = string
  default     = "t2.micro"

  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.instance_type)
    error_message = "Apenas t2.micro e t3.micro sao aceitos: sao os unicos tipos elegiveis ao free tier de EC2."
  }
}

variable "root_volume_size_gb" {
  description = "Tamanho do volume raiz em GB. O free tier de EBS cobre 30 GB."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 30
    error_message = "Use entre 8 e 30 GB. Acima de 30 GB o volume sai do limite do free tier de EBS."
  }
}

variable "swap_size_mb" {
  description = "Tamanho do arquivo de swap em MB. Necessario porque t2.micro tem apenas 1 GB de RAM e precisa rodar MariaDB, PHP-FPM e nginx ao mesmo tempo."
  type        = number
  default     = 2048

  validation {
    condition     = var.swap_size_mb >= 512 && var.swap_size_mb <= 4096
    error_message = "Use entre 512 e 4096 MB de swap."
  }
}

# ==============================================================================
# Acesso administrativo
# ==============================================================================

variable "allowed_ssh_cidrs" {
  description = "CIDRs autorizados na porta 22. Lista vazia (padrao) nao cria nenhuma regra de SSH: o comportamento padrao e fail-closed. O acesso administrativo primario e o SSM Session Manager, que nao exige porta aberta."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.allowed_ssh_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 na porta 22 e proibido. Informe seu IP publico com mascara /32."
  }

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Todo item de allowed_ssh_cidrs deve ser um CIDR valido, por exemplo 203.0.113.10/32."
  }
}

variable "ssh_public_key" {
  description = "Conteudo da chave publica SSH, por exemplo ssh-ed25519 AAAA... Vazio (padrao) nao cria key pair. A chave privada nunca passa pelo Terraform e portanto nunca entra no state."
  type        = string
  default     = ""
}

# ==============================================================================
# WordPress
# ==============================================================================

variable "wordpress_db_name" {
  description = "Nome do banco de dados do WordPress."
  type        = string
  default     = "wordpress"
}

variable "wordpress_db_user" {
  description = "Usuario do banco do WordPress. Nao e o root do MariaDB: o WordPress recebe um usuario dedicado com privilegio apenas no proprio banco."
  type        = string
  default     = "wp_user"
}

variable "wordpress_site_title" {
  description = "Titulo do site WordPress."
  type        = string
  default     = "Desafio Terraform"
}

variable "wordpress_admin_user" {
  description = "Usuario administrador do WordPress. Deliberadamente diferente de admin, que e o primeiro nome tentado por qualquer ataque de forca bruta."
  type        = string
  default     = "duh_ops"

  validation {
    condition     = !contains(["admin", "administrator", "root", "wordpress"], lower(var.wordpress_admin_user))
    error_message = "Nomes previsiveis (admin, administrator, root, wordpress) sao proibidos por serem alvo padrao de forca bruta."
  }
}

variable "wordpress_admin_email" {
  description = "E-mail do administrador do WordPress. Mantido como placeholder porque este repositorio e publico e e-mail versionado e alvo de coleta automatizada."
  type        = string
  default     = "admin@example.com"
}
