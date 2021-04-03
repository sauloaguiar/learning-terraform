provider "aws" {
  region = "us-east-1"
  # never put sensitive data in the configuration file
  # refer to the readme file on how to use it
}


resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_blocks
  
  // adding or removing attributes will add/remove them in the aws resource automatically
  tags = {
    Name = "${var.env_prefix}-vpc",
  }
}

module "myapp-subnet" {
  source = "./modules/subnet"
  subnet_cidr_blocks = var.subnet_cidr_block
  avail_zone = var.avail_zone
  env_prefix = var.env_prefix
  vpc_id = aws_vpc.myapp-vpc.id
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id
}

resource "aws_default_security_group" "default-sg" {
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
      cidr_blocks = [ var.my_ip ]
      from_port = 22
      protocol = "tcp"
      to_port = 22
    }
  ingress {
      cidr_blocks = [ "0.0.0.0/0" ]
      from_port = 8080
      protocol = "tcp"
      to_port = 8080
    }

  egress {
    cidr_blocks = [ "0.0.0.0/0" ]
    from_port = 0
    prefix_list_ids = []
    protocol = "-1"
    to_port = 0
  } 

  tags = {
    Name = "${var.env_prefix}-default-sg"
  }
  
}

data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
}


resource "aws_key_pair" "ssh-key" {
  key_name = "server-key"

  # read from a local public key file
  # use `ssh -i <path_to_private_key_locally> ec2-user@<public-ip>
  # -i <path_to_private_key_locally> is actually the default, so `ssh ec2-user@ip` will do it
  public_key = file(var.public_key_location)
}

resource "aws_instance" "myapp-server" {
  # instance configuration (required fields)
  ami = data.aws_ami.latest-amazon-linux-image.id
  instance_type = var.instance_type

  # networking configuration (let's put this instance within our vpc)
  subnet_id = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids = [ aws_default_security_group.default-sg.id ]
  availability_zone = var.avail_zone

  # enable this to be access from public
  associate_public_ip_address = true

  key_name = aws_key_pair.ssh-key.key_name

  # this will be executed in the ec2 instance once it's up and running
  # we're passing data to aws ec2
  user_data = file("entry-script.sh")

  # provisioner "file" {
  #   source = "entry-script.sh"
  #   destination = "/home/ec2-user/entry-script-on-ec2.sh"
  # }

  # provisioner "remote-exec" {
  #   # this will execute in the remote ec2 instance that just got created
  #   # notice that the file got copied to the remote ec2 instance in the provisioner above
  #   script = file("entry-script-on-ec2.sh")
  # }
  
  # provisioner "local-exec" {
  #   # this will execute in the machine that execute terraform
  #   command = "echo ${self.public_ip} > output.txt"
  # }
  tags = {
    "name" = "${var.env_prefix}-server"
  }
}