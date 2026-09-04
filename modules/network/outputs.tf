output "vpc_id" {
  description = "ID da VPC criada."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID da subnet publica onde a instancia sera criada."
  value       = aws_subnet.public.id
}

output "availability_zone" {
  description = "Availability zone efetivamente usada pela subnet publica."
  value       = aws_subnet.public.availability_zone
}
