
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "ShopFlow-VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ShopFlow-IGW"
  }
}

resource "aws_subnet" "publicsubnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24" 
  availability_zone = "us-east-1a"
  tags = {
    Name = "ShopFlow-subnet1"
  }
}

resource "aws_subnet" "publicsubnet2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "ShopFlow-subnet2"
  }
}

resource "aws_route_table" "publicroutetable" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "ShopFlow-route1"
  }
}

resource "aws_route" "publicroute" {
  route_table_id         = aws_route_table.publicroutetable.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "publicrouteassoc1" {
  subnet_id      = aws_subnet.publicsubnet1.id
  route_table_id = aws_route_table.publicroutetable.id
}

resource "aws_route_table_association" "publicrouteassoc2" {
  subnet_id      = aws_subnet.publicsubnet2.id
  route_table_id = aws_route_table.publicroutetable.id
}

resource "aws_subnet" "privatesubnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "ShopFlow-PrivateSubnet"
  }
}

resource "aws_subnet" "privatesubnet2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "ShopFlow-PrivateSubnet2"
  }
}

resource "aws_db_subnet_group" "rds-group" {
  name = "shopflow-rds-group"
  subnet_ids = [aws_subnet.privatesubnet1.id, aws_subnet.privatesubnet2.id]
}

resource "aws_elasticache_subnet_group" "elasticache" {
  name = "shopflow-elasticache-group"
  subnet_ids = [aws_subnet.privatesubnet1.id, aws_subnet.privatesubnet2.id]
}

resource "aws_nat_gateway" "nat-gw" {
  subnet_id = aws_subnet.publicsubnet1.id
  allocation_id = aws_eip.nat-eip.id
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "ShopFlow-NAT"
  }
}

resource "aws_eip" "nat-eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "ShopFlow-EIP"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_access" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat-gw.id
}

resource "aws_route_table_association" "private_rt_assoc_a" {
  subnet_id      = aws_subnet.privatesubnet1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_rt_assoc_b" {
  subnet_id      = aws_subnet.privatesubnet2.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "alb-sg" {
  vpc_id      = aws_vpc.main.id
  name_prefix = "public-app-sg"
  description = "Allow public web traffic"
  tags = {
    Name = "ALB-SG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.alb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  security_group_id = aws_security_group.alb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.alb-sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "ecs-sg" {
  vpc_id = aws_vpc.main.id
  name_prefix = "Ecs-SG"
  description = "Allow traffic from ALB sg"
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ECS-SG"
  }
}


resource "aws_security_group" "rds_sg" {
  vpc_id      = aws_vpc.main.id
  name_prefix = "private-app-sg"
  description = "Allow traffic from ecs sg"
  tags = {
    Name = "RDS-SG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.ecs-sg.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_security_group" "cache-sg" {
  vpc_id = aws_vpc.main.id
  name_prefix = "Cache-SG"
  description = "Allow traffic from ecs sg"
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs-sg.id]
  }
  tags = {
    Name = "Cache-SG"
  }
}

resource "aws_kms_key" "main" {
  description = "ShopFlow encryption key for RDS, S3, Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation = true
}

resource "aws_kms_alias" "main" {
  name = "alias/shopflow-key"
  target_key_id = aws_kms_key.main.key_id
}