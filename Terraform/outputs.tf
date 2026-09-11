output "vpc_id" {
  description = "TravelPlanner VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "k3s_instance_id" {
  description = "K3s EC2 instance ID"
  value       = aws_instance.k3s.id
}

output "k3s_public_ip" {
  description = "K3s EC2 public IP"
  value       = aws_instance.k3s.public_ip
}

output "postgres_instance_id" {
  description = "PostgreSQL EC2 instance ID"
  value       = aws_instance.postgres.id
}

output "postgres_private_ip" {
  description = "PostgreSQL private IP"
  value       = aws_instance.postgres.private_ip
}