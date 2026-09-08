terraform {
  required_version = ">= 1.5.0"

  # Modulo declara o provider que consome, mas nunca configura um bloco
  # "provider". Quem define regiao e credencial e sempre a raiz.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63"
    }
  }
}
