# ==============================================================================
# Composicao do ambiente. Este arquivo apenas liga os modulos: nenhum recurso
# e declarado diretamente aqui.
# ==============================================================================

locals {
  # Prefixo unico de nomenclatura, derivado das variaveis e nunca hardcoded.
  # Todo nome de recurso do projeto comeca por ele.
  name_prefix = "${var.project_name}-${var.environment}"
}

module "network" {
  source = "./modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}
