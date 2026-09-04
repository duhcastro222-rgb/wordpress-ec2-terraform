provider "aws" {
  region = var.aws_region

  # default_tags aplica estas tags a todo recurso que suporte tag, sem repeticao
  # manual em cada bloco. Nesta conta, que e compartilhada com outro projeto, a
  # tag Owner e o que permite identificar e destruir apenas o que e nosso.
  default_tags {
    tags = {
      Project     = "${var.project_name}-desafio"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
