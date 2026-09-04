# ==============================================================================
# Composicao do ambiente. Este arquivo apenas liga os modulos: nenhum recurso
# e declarado diretamente aqui.
# ==============================================================================

locals {
  # Prefixo unico de nomenclatura, derivado das variaveis e nunca hardcoded.
  # Todo nome de recurso do projeto comeca por ele: newchance-dev-*
  name_prefix = "${var.project_name}-${var.environment}"

  # Namespace dos segredos no SSM Parameter Store: /newchance/dev/*
  # Mesma origem do name_prefix, para que recurso e segredo nunca divirjam.
  ssm_path_prefix = "/${var.project_name}/${var.environment}"
}

module "network" {
  source = "./modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "wordpress" {
  source = "./modules/wordpress"

  name_prefix     = local.name_prefix
  ssm_path_prefix = local.ssm_path_prefix
  aws_region      = var.aws_region

  vpc_id    = module.network.vpc_id
  vpc_cidr  = var.vpc_cidr
  subnet_id = module.network.public_subnet_id

  instance_type       = var.instance_type
  root_volume_size_gb = var.root_volume_size_gb
  swap_size_mb        = var.swap_size_mb

  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  ssh_public_key    = var.ssh_public_key

  db_name     = var.wordpress_db_name
  db_user     = var.wordpress_db_user
  site_title  = var.wordpress_site_title
  admin_user  = var.wordpress_admin_user
  admin_email = var.wordpress_admin_email
}
