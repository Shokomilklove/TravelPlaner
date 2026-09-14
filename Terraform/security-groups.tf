resource "aws_security_group" "k3s" {
  name        = "travel-planner-k3s-sg"
  description = "Security group for TravelPlanner K3s server"
  vpc_id      = aws_vpc.main.id

  # HTTP — публичный доступ к приложению
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — публичный доступ к приложению
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # K3s API — НЕ открываем в Internet.
  # Администрирование через AWS SSM.

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "travel-planner-k3s-sg"
    Project = "TravelPlanner"
  }
}

resource "aws_security_group" "postgres" {
  name        = "travel-planner-postgres-sg"
  description = "Security group for TravelPlanner PostgreSQL"
  vpc_id      = aws_vpc.main.id

  # PostgreSQL доступен только из K3s Security Group
  ingress {
    description     = "PostgreSQL from K3s"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "travel-planner-postgres-sg"
    Project = "TravelPlanner"
  }
}