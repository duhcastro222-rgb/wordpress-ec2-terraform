variable "name_prefix" {
  description = "Prefixo aplicado ao nome de todo recurso do modulo, no formato {project}-{environment}."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR da subnet publica, contido em vpc_cidr."
  type        = string
}
