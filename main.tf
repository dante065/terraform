# terraform {
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 5.0"
#     }
#   }
# }

# Configure the AWS Provider
provider "aws" {
  region = "ap-northeast-1"
  
}


variable "subnet_prefix"{
  description = "CIDR block for the subnet"
  #default = "10.0.1.0/24"
  #type = string
   
}
#10.0.1.0/24
#1 create vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}
#2 create Internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

  
}
#3 Create custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}
#4 create a subnet ,  passing subnet_prefix via variable, refer to list number 1
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = var.subnet_prefix[0].cidr_block
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = var.subnet_prefix[0].name
  }
}

#refer to list number 2
resource "aws_subnet" "subnet-2" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = var.subnet_prefix[1].cidr_block
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = var.subnet_prefix[1].name
  }
}

#5 associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}
#6 create security group to allow port 22, 80, 443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  tags = {
    Name = "allow_web"
  }

  ingress {
    description = "HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#7 create a network interface with an IP in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

  # attachment {
  #   instance     = aws_instance.test.id
  #   device_index = 1
  # }
}
#8 Assign an Elastic IP to the network interface created in step 7
#relies on the deployment of internet gateway(IG has to be deployed first before EIP)
resource "aws_eip" "eip-1" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [ aws_internet_gateway.gw ]
}

#check whether the resources have been created during deployment 
output "server_public_ip"{
  value = aws_eip.eip-1.public_ip
}

#9 Create Ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
  ami = "ami-0a0b7b240264a48d7"
  instance_type = "t2.micro"
  #hardcore AZ as AWS will randomly deploy the resources on their AZs
  availability_zone = "ap-northeast-1a"
  key_name = "main-key"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user_data.log|logger -t user_data_script -s 2>/dev/console) 2>&1

              echo "Starting user_data script"

              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2

              echo "Your server is up and running!" | sudo tee /var/www/html/index.html
              EOF
  
  tags = {
    Name = "web-server-testing"
  }
  
}

output "server_privateip"{
  value = aws_instance.web-server-instance.private_ip
}


