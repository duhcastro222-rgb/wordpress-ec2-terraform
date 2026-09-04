# ==============================================================================
# Instancia WordPress: security group, identidade IAM, segredos no SSM e a EC2
# com bootstrap por cloud-init.
# ==============================================================================

# AMI mais recente do Amazon Linux 2023. Nenhum ID de AMI e fixado no codigo:
# ID de AMI e regional e envelhece, o que faria o projeto parar de funcionar em
# outra regiao ou depois do proximo release de imagem.
#
# Nota: o caminho publico do SSM Parameter Store para esta AMI
# (/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64) foi
# verificado e nao retorna valor nesta conta e regiao, por isso a busca e feita
# por filtro de describe-images.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Chave KMS gerenciada pela AWS que cifra os SecureString do Parameter Store.
# Buscada pelo alias para que a policy IAM referencie o ARN real da chave: uma
# policy de kms:Decrypt precisa apontar para a chave, nao para o alias.
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

# ==============================================================================
# Segredos
#
# Gerados aqui e gravados no SSM Parameter Store. A instancia os le em tempo de
# boot usando sua role IAM. Motivo de nao passa-los pelo user_data: o user_data
# fica legivel por qualquer processo da instancia via IMDS e por qualquer
# principal com ec2:DescribeInstanceAttribute. Segredo em user_data e o erro
# mais comum neste tipo de provisionamento.
#
# Comprimento em vez de complexidade: 40 caracteres alfanumericos dao cerca de
# 238 bits de entropia, muito acima de qualquer exigencia. Excluir simbolos
# tambem elimina uma classe inteira de bug de escape no script de bootstrap,
# que roda sem possibilidade de depuracao interativa.
# ==============================================================================

resource "random_password" "db" {
  length  = 40
  special = false
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "${var.ssm_path_prefix}/db/password"
  description = "Senha do usuario do banco do WordPress. Lida no boot pela role da instancia."
  type        = "SecureString"
  value       = random_password.db.result
  key_id      = data.aws_kms_alias.ssm.target_key_id

  # Standard e gratuito ate 10.000 parametros. Advanced e cobrado por parametro.
  tier = "Standard"

  tags = {
    Name = "${var.name_prefix}-ssm-db-password"
  }
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "${var.ssm_path_prefix}/wordpress/admin-password"
  description = "Senha do administrador do WordPress. Lida no boot pela role da instancia."
  type        = "SecureString"
  value       = random_password.admin.result
  key_id      = data.aws_kms_alias.ssm.target_key_id
  tier        = "Standard"

  tags = {
    Name = "${var.name_prefix}-ssm-admin-password"
  }
}

# ==============================================================================
# Identidade IAM da instancia
# ==============================================================================

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "PermitirQueEC2AssumaEstaRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-role-ec2"
  description        = "Role da instancia WordPress: le apenas os proprios segredos e habilita SSM Session Manager."
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.name_prefix}-role-ec2"
  }
}

# Menor privilegio: a instancia le exatamente os dois parametros deste projeto,
# nomeados por ARN, e decifra apenas com a chave que os cifrou. Nao ha curinga
# em nenhum dos dois statements.
data "aws_iam_policy_document" "ssm_read" {
  statement {
    sid    = "LerApenasOsSegredosDesteProjeto"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]

    resources = [
      aws_ssm_parameter.db_password.arn,
      aws_ssm_parameter.admin_password.arn,
    ]
  }

  statement {
    sid    = "DecifrarSomenteComAChaveDoSSM"
    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = [data.aws_kms_alias.ssm.target_key_arn]

    # Restringe o uso da chave ao servico SSM: mesmo tendo kms:Decrypt, a
    # instancia nao consegue decifrar dado de outro servico com esta chave.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ssm_read" {
  name   = "${var.name_prefix}-policy-ssm-read"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ssm_read.json
}

# Policy gerenciada pela AWS que habilita o SSM Session Manager. Permite acesso
# administrativo a instancia sem chave SSH e sem porta aberta, com registro no
# CloudTrail. Porta 22 continua existindo e restrita, mas este e o caminho bom.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-profile-ec2"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.name_prefix}-profile-ec2"
  }
}

# ==============================================================================
# Security group
#
# Regras declaradas como recursos separados (aws_vpc_security_group_*_rule) e
# nao como blocos inline. Regra inline e substituida em bloco a cada mudanca, o
# que derruba conexao existente; recurso separado tem ciclo de vida proprio e
# aparece individualmente no plan, o que torna auditavel qual porta abriu.
# ==============================================================================

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-sg-web"
  description = "Trafego da instancia WordPress: HTTP publico, SSH restrito e egress limitado."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-sg-web"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP publico: o site precisa ser alcancavel por qualquer browser"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80

  tags = {
    Name = "${var.name_prefix}-sgr-in-http"
  }
}

# Uma regra por CIDR autorizado. Lista vazia nao cria regra alguma: sem valor
# em allowed_ssh_cidrs a porta 22 simplesmente nao existe no grupo.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "SSH restrito a origem autorizada"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22

  tags = {
    Name = "${var.name_prefix}-sgr-in-ssh"
  }
}

# ------------------------------------------------------------------------------
# Egress explicito.
#
# O padrao que quase todo projeto deixa passar e uma regra unica de saida
# liberando todo protocolo para 0.0.0.0/0. Isso significa que, uma vez
# comprometida, a instancia pode falar com qualquer host em qualquer porta:
# canal de comando e controle, exfiltracao para servidor arbitrario,
# participacao em ataque a terceiro. Restringir a saida nao impede a invasao,
# mas encurta muito o que o atacante consegue fazer depois dela.
# ------------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS de saida: repositorios dnf, endpoints do SSM, wordpress.org"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = {
    Name = "${var.name_prefix}-sgr-out-https"
  }
}

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP de saida: redirecionamentos e verificacao de revogacao de certificado"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80

  tags = {
    Name = "${var.name_prefix}-sgr-out-http"
  }
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.web.id
  description       = "DNS UDP restrito ao resolver da propria VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53

  tags = {
    Name = "${var.name_prefix}-sgr-out-dns-udp"
  }
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.web.id
  description       = "DNS TCP restrito ao resolver da propria VPC, para resposta que excede UDP"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53

  tags = {
    Name = "${var.name_prefix}-sgr-out-dns-tcp"
  }
}

resource "aws_vpc_security_group_egress_rule" "ntp" {
  security_group_id = aws_security_group.web.id
  description       = "NTP de saida: relogio fora de sincronia invalida assinatura de request AWS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "udp"
  from_port         = 123
  to_port           = 123

  tags = {
    Name = "${var.name_prefix}-sgr-out-ntp"
  }
}

# ==============================================================================
# Par de chaves SSH
#
# Criado somente se uma chave publica for informada. O Terraform recebe apenas
# a parte publica: a chave privada nunca passa pelo codigo nem pelo state.
# ==============================================================================

resource "aws_key_pair" "admin" {
  count = var.ssh_public_key != "" ? 1 : 0

  key_name   = "${var.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.name_prefix}-key"
  }
}

# ==============================================================================
# Instancia
# ==============================================================================

resource "aws_instance" "wordpress" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Explicito porque a subnet nao atribui IP publico automaticamente.
  associate_public_ip_address = true

  key_name = var.ssh_public_key != "" ? aws_key_pair.admin[0].key_name : null

  # IMDSv2 obrigatorio. Com IMDSv1 basta um GET simples para o endpoint de
  # metadados retornar a credencial temporaria da role; qualquer vulnerabilidade
  # de SSRF na aplicacao vira roubo de credencial da conta AWS. Exigir token
  # PUT com hop limit 1 fecha esse caminho.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb

    # Cifragem em repouso com a chave gerenciada da AWS: sem custo adicional e
    # sem motivo para nao usar.
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.name_prefix}-ebs-root"
    }
  }

  # Monitoramento detalhado (metricas de 1 minuto) e cobrado. O padrao de
  # 5 minutos e gratuito e suficiente aqui.
  monitoring = false

  # Comprimido com gzip antes de enviar. A AWS limita user_data a 16.384 bytes
  # e este script, com a documentacao das decisoes, ocupa cerca de 17 KB. O
  # cloud-init detecta e descomprime gzip automaticamente, e o script cai para
  # cerca de 6,6 KB, ou 40% do limite. A alternativa seria remover comentario
  # para caber, o que trocaria documentacao por espaco sem necessidade.
  user_data_base64 = base64gzip(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region       = var.aws_region
    swap_size_mb     = var.swap_size_mb
    db_name          = var.db_name
    db_user          = var.db_user
    db_password_ssm  = aws_ssm_parameter.db_password.name
    adm_password_ssm = aws_ssm_parameter.admin_password.name
    site_title       = var.site_title
    admin_user       = var.admin_user
    admin_email      = var.admin_email
  }))

  # Mudanca no script de bootstrap recria a instancia. Sem isso o Terraform
  # apenas atualiza o atributo e o script novo nunca roda, deixando o estado
  # real divergente do codigo de forma silenciosa.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name_prefix}-ec2"
  }

  depends_on = [
    aws_iam_role_policy.ssm_read,
    aws_iam_role_policy_attachment.ssm_core,
  ]
}
