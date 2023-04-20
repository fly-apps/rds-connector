variable "aws_account" { 
  type = string 
}

variable "rds_password" { 
  type = string
} 

resource "aws_key_pair" "ssh_key" { 
  key_name = "rds-root-deploy-key"
  public_key = file("~/.ssh/YOUR_SSH_KEY.pub")
}

module "vpc" { 
  source = "terraform-aws-modules/vpc/aws"

  name = "rds-vpc"
  cidr = "172.16.0.0/16"

  azs = ["us-east-1a", "us-east-1b"]
  private_subnets = ["172.16.1.0/24", "172.16.2.0/24"]
  public_subnets = ["172.16.101.0/24", "172.16.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  tags = { 
    Terraform = "true"
    Environment = "dev"
  }
} 

data "aws_ami" "ubuntu" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "ingress-ssh-all" {
    name = "allow-all-sg"
    vpc_id = module.vpc.vpc_id 
    ingress {
        cidr_blocks = [
          "0.0.0.0/0"
        ]
        from_port = 22
        to_port = 22
        protocol = "tcp"
    }

    egress {
       from_port = 0
       to_port = 0
       protocol = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }
}

module "allow_postgres" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "postgres-service"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 5432
      protocol    = "tcp"
      description = "postgres"
      cidr_blocks = "172.16.0.0/16"
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule = "all-all"
    },
  ]
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  engine = "postgres"
  engine_version = "9.6.9"
  major_engine_version = "9.6"
  
  family = "postgres9.6"
  instance_class = "db.m3.medium"
  allocated_storage = 5

  name = "appdb"
  username = "postgres"
  password = var.rds_password 
  port = 5432

  subnet_ids = module.vpc.public_subnets
  vpc_security_group_ids = [module.allow_postgres.this_security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  identifier = "rds-appdb"
}

resource "aws_instance" "rds-gw" {
    ami = data.aws_ami.ubuntu.id
    instance_type = "t2.micro"
    key_name = aws_key_pair.ssh_key.key_name
    subnet_id = module.vpc.public_subnets[0]
    security_groups = [aws_security_group.ingress-ssh-all.id]
  
    provisioner "file" { 
        source = "wg0.conf" 
        destination = "/tmp/wg0.conf"
	connection { 
	    type     = "ssh"
            user     = "ubuntu"
            host     = self.public_ip
            private_key = file("~/.ssh/YOUR_SSH_KEY")
 	} 
    }

    provisioner "file" { 
        destination = "/tmp/pgbouncer.ini"
        content = templatefile("pgbouncer.ini.tmpl", { 
			rds_host = module.db.this_db_instance_address,
			rds_pass = var.rds_password,
		})
	connection { 
	    type     = "ssh"
            user     = "ubuntu"
            host     = self.public_ip
            private_key = file("~/.ssh/YOUR_SSH_KEY")
 	} 
    }

    provisioner "file" { 
        destination = "/tmp/userlist.txt"
        source = "userlist.txt"
	connection { 
	    type     = "ssh"
            user     = "ubuntu"
            host     = self.public_ip
            private_key = file("~/.ssh/YOUR_SSH_KEY")
 	}   
    }

    provisioner "remote-exec" {
        inline = [
	    "sudo apt update",
	    "sudo apt update",
	    "sudo apt install -y wireguard resolvconf pgbouncer postgresql-client",
            "sudo mv /tmp/wg0.conf /etc/wireguard",
	    "sudo cp /tmp/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini",
	    "sudo cp /tmp/userlist.txt /etc/pgbouncer/userlist.txt",
            "sudo systemctl restart pgbouncer",
            "sudo /usr/bin/wg-quick up wg0",
	    "sudo systemctl enable wg-quick@wg0.service",
        ]
	connection { 
	    type     = "ssh"
            user     = "ubuntu"
            host     = self.public_ip
            private_key = file("~/.ssh/YOUR_SSH_KEY")
 	} 
    } 
}

