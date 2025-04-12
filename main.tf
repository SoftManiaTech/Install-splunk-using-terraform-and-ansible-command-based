terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

# Fetch Latest RHEL AMI
data "aws_ami" "latest_rhel" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["RHEL-9.0*"]
  }
}

# Security Group
resource "aws_security_group" "splunk_sg" {
  name        = "splunk-security-group"
  description = "Allow Splunk ports"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create EC2 Instance
resource "aws_instance" "splunk_server" {
  ami                    = data.aws_ami.latest_rhel.id
  instance_type          = "t2.medium"
  key_name               = var.key_name
  security_groups        = [aws_security_group.splunk_sg.name]

  # Inject Ansible SSH Public Key
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }

    inline = [
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys"
    ]
  }

  tags = {
    Name = "Splunk-Server"
  }
}

# Generate Ansible Inventory File
resource "local_file" "inventory" {
  content = <<EOT
[splunk]
${aws_instance.splunk_server.public_ip} ansible_user=ec2-user
EOT
  filename = "${path.module}/inventory.ini"
}