# Configure the AWS Provider
provider "aws" {
  access_key = "<ACCESS_KEY_HERE>"
  secret_key = "<SECRET_KEY_HERE>"
  region     = "eu-central-1"
}

# Create VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "prod"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "prod_igw" {
  vpc_id = aws_vpc.prod_vpc.id
}

# Create Route Table
resource "aws_route_table" "prod_route_table" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_igw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.prod_igw.id
  }

  tags = {
    Name = "prod"
  }
}

# Create Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "Public"
  }
}

# Create Route Association
resource "aws_route_table_association" "ta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.prod_route_table.id
}

# Create Security Group
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow inbound web traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = -1
    to_port = -1
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Create network interface with a private IP in the subnet
resource "aws_network_interface" "network_interface" {
  subnet_id       = aws_subnet.public_subnet.id
  private_ips     = [var.private_ip]
  security_groups = [aws_security_group.allow_web.id]
}

# Assign elastic IP to network interface
resource "aws_eip" "eip" {
  network_interface         = aws_network_interface.network_interface.id
  vpc                       = true
  associate_with_private_ip = var.private_ip
  depends_on                = [aws_internet_gateway.prod_igw]
}

output "server_public_ip" {
    value = aws_eip.eip.public_ip
}

# Create EC2 instance with web server
resource "aws_instance" "web-server" {
  ami               = "ami-08c148bb835696b45"
  instance_type     = "t2.micro"
  availability_zone = "eu-central-1a"
  key_name = "ec2-key"
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.network_interface.id
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              service httpd start
              chkconfig httpd on
              bash -c 'echo fancy apache web server. > /var/www/html/index.html'
              EOF
  tags = {
    Name = "web-server"
  }
}

variable "private_ip" {
    description = "holds private IP"
}