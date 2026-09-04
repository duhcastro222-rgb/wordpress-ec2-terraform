# ==============================================================================
# Identificacao
# ==============================================================================

variable "name_prefix" {
  description = "Prefixo aplicado ao nome de todo recurso do modulo, no formato {project}-{environment}."
  type        = string
}

variable "ssm_path_prefix" {
  description = "Prefixo do caminho dos parametros no SSM Parameter Store, por exemplo /wordpress/dev."
  type        = string
}

variable "aws_region" {
  description = "Regiao AWS. Usada na condicao kms:ViaService da policy e nas chamadas da AWS CLI dentro do bootstrap."
  type        = string
}

# ==============================================================================
# Rede recebida do modulo network
# ==============================================================================

variable "vpc_id" {
  description = "ID da VPC onde o security group sera criado."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Usado para restringir o egress de DNS ao resolver da propria VPC."
  type        = string
}

variable "subnet_id" {
  description = "ID da subnet publica onde a instancia sera criada."
  type        = string
}

# ==============================================================================
# Instancia
# ==============================================================================

variable "instance_type" {
  description = "Tipo da instancia EC2."
  type        = string
}

variable "root_volume_size_gb" {
  description = "Tamanho do volume raiz em GB."
  type        = number
}

variable "swap_size_mb" {
  description = "Tamanho do arquivo de swap em MB."
  type        = number
}

# ==============================================================================
# Acesso administrativo
# ==============================================================================

variable "allowed_ssh_cidrs" {
  description = "CIDRs autorizados na porta 22. Lista vazia nao cria nenhuma regra de SSH."
  type        = list(string)
}

variable "ssh_public_key" {
  description = "Conteudo da chave publica SSH. Vazio nao cria key pair."
  type        = string
}

# ==============================================================================
# WordPress
# ==============================================================================

variable "db_name" {
  description = "Nome do banco de dados do WordPress."
  type        = string
}

variable "db_user" {
  description = "Usuario dedicado do banco do WordPress."
  type        = string
}

variable "site_title" {
  description = "Titulo do site WordPress."
  type        = string
}

variable "admin_user" {
  description = "Usuario administrador do WordPress."
  type        = string
}

variable "admin_email" {
  description = "E-mail do administrador do WordPress."
  type        = string
}
