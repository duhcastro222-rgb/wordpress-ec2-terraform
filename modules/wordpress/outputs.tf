output "instance_id" {
  description = "ID da instancia EC2, usado para abrir sessao via SSM Session Manager."
  value       = aws_instance.wordpress.id
}

output "public_ip" {
  description = "IP publico da instancia."
  value       = aws_instance.wordpress.public_ip
}

output "wordpress_url" {
  description = "URL do site WordPress."
  value       = "http://${aws_instance.wordpress.public_ip}"
}

output "security_group_id" {
  description = "ID do security group da instancia."
  value       = aws_security_group.web.id
}

output "admin_password_ssm_parameter" {
  description = "Caminho do parametro SSM com a senha do administrador do WordPress. O valor nao e exposto como output: leia com aws ssm get-parameter --with-decryption."
  value       = aws_ssm_parameter.admin_password.name
}

output "db_password_ssm_parameter" {
  description = "Caminho do parametro SSM com a senha do banco. O valor nao e exposto como output."
  value       = aws_ssm_parameter.db_password.name
}
