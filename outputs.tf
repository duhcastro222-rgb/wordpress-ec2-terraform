# ==============================================================================
# Outputs
#
# Nenhum segredo e exposto como output, nem mesmo marcado como sensitive: o
# valor de um output sensitive continua gravado em texto claro no state e pode
# ser lido com "terraform output -json". Em vez do valor, o output entrega o
# COMANDO que busca o valor com a credencial de quem executa.
# ==============================================================================

output "wordpress_url" {
  description = "URL do site WordPress. Abra no browser."
  value       = module.wordpress.wordpress_url
}

output "wordpress_admin_url" {
  description = "URL do painel administrativo do WordPress."
  value       = "${module.wordpress.wordpress_url}/wp-admin"
}

output "wordpress_admin_user" {
  description = "Usuario administrador do WordPress."
  value       = var.wordpress_admin_user
}

output "instance_id" {
  description = "ID da instancia EC2."
  value       = module.wordpress.instance_id
}

output "instance_public_ip" {
  description = "IP publico da instancia."
  value       = module.wordpress.public_ip
}

output "comando_senha_admin" {
  description = "Comando para recuperar a senha do administrador do WordPress a partir do SSM Parameter Store."
  value       = "aws ssm get-parameter --name ${module.wordpress.admin_password_ssm_parameter} --with-decryption --region ${var.aws_region} --query Parameter.Value --output text"
}

output "comando_sessao_ssm" {
  description = "Comando para abrir shell na instancia via SSM Session Manager, sem chave SSH e sem porta aberta."
  value       = "aws ssm start-session --target ${module.wordpress.instance_id} --region ${var.aws_region}"
}

output "comando_log_bootstrap" {
  description = "Comando para ler o log do bootstrap na instancia sem abrir sessao interativa."
  value       = "aws ssm send-command --instance-ids ${module.wordpress.instance_id} --document-name AWS-RunShellScript --parameters commands='tail -50 /var/log/wordpress-bootstrap.log' --region ${var.aws_region}"
}
