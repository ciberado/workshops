locals {
  ubuntu = "099720109477"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.prefix}_app_sg"
  description = "Application security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from Anywhere"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Layer : "network fabric"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [local.ubuntu]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}


resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/pokemon.sh.tpl", {
    port  = var.port
  })

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
    http_tokens            = "optional"
  }

  tags = {
    Name : "pokemon-server"
    Layer : "computing"
  }
}

output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "subnet_id" {
  value = data.aws_subnets.default.ids[0]
}

output "instance_public_ip" {
  description = "Address of the application"
  value       = "http://${aws_instance.app.public_ip}:${var.port}"
}