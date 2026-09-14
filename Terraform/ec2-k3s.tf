resource "aws_instance" "k3s" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "m7i-flex.large"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ssm.name

  user_data_base64            = base64gzip(local.k3s_bootstrap)
  user_data_replace_on_change = true

  tags = {
    Name    = "travel-planner-k3s"
    Project = "TravelPlanner"
  }
}

resource "aws_ebs_volume" "k3s_data" {
  availability_zone = aws_instance.k3s.availability_zone
  size              = 30
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "travel-planner-k3s-data"
    Project = "TravelPlanner"
  }
}

resource "aws_volume_attachment" "k3s_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.k3s_data.id
  instance_id = aws_instance.k3s.id
}