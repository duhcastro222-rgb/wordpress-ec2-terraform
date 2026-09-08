# ==============================================================================
# Rede minima para uma instancia publica: VPC, uma subnet publica, Internet
# Gateway e tabela de rotas.
#
# Deliberadamente ausentes:
#   - NAT Gateway: custa cerca de USD 32/mes e so serve para dar saida a
#     subnet privada, que este projeto nao tem.
#   - Subnet privada: o banco roda na propria instancia, portanto nao existe
#     recurso para isolar.
#   - Segunda AZ: nao ha Auto Scaling nem load balancer para aproveitar.
# ==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Primeira AZ disponivel da regiao. Em us-east-1 resolve para us-east-1a,
  # que oferece tanto t2.micro quanto t3.micro (a us-east-1e nao oferece
  # t3.micro, motivo pelo qual nao escolhemos uma AZ aleatoria).
  availability_zone = data.aws_availability_zones.available.names[0]

  # "us-east-1a" -> "1a", para compor o nome da subnet conforme a convencao.
  availability_zone_suffix = element(split("-", local.availability_zone), 2)
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Ambos necessarios: o agente do SSM resolve nomes publicos para alcancar os
  # endpoints da AWS, e o dnf resolve os repositorios do Amazon Linux.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Toda VPC nasce com um security group default que libera todo o trafego entre
# seus membros. Declarar este recurso sem nenhum bloco ingress/egress faz o
# Terraform adotar esse SG e remover todas as regras dele. Se algum recurso for
# criado sem SG explicito no futuro, ele cai num grupo que nao permite nada, em
# vez de cair num grupo permissivo.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-sg-default-bloqueado"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = local.availability_zone

  # false de proposito. Com true, toda instancia criada nesta subnet ganharia
  # IP publico automaticamente, inclusive uma que nao deveria ter. A atribuicao
  # fica explicita na instancia que precisa (associate_public_ip_address),
  # porque IP publico deve ser decisao consciente, nao heranca da subnet.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-subnet-public-${local.availability_zone_suffix}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-rtb-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
