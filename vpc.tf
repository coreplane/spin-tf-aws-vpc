# VPC setup

resource "aws_vpc" "default" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  tags = "${
    map(
      "Name", "${var.sitename}",
      "Terraform", "true",
      "kubernetes.io/cluster/${var.sitename}", "shared",
      )
  }"
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
  tags {
    Name = "${var.sitename}"
    Terraform = "true"
  }
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.default.id}"
  count = "${length(var.azlist)}"
  cidr_block = "${lookup(var.az_subnet_cidrs, var.azlist[count.index])}"
  availability_zone = "${var.azlist[count.index]}"
  map_public_ip_on_launch = true
  depends_on = ["aws_internet_gateway.default"]
  tags = "${
    map(
      "Name", "${var.sitename}-public-${var.azlist[count.index]}",
      "Terraform", "true",
      "kubernetes.io/cluster/${var.sitename}", "shared",
      )
  }"
  lifecycle = { create_before_destroy = true }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }
  tags {
    Name = "${var.sitename}"
    Terraform = "true"
  }
}

resource "aws_route_table_association" "public" {
  count = "${length(var.azlist)}"
  subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_db_subnet_group" "db_subnet_group" {
    name = "${var.sitename}-db"
    description = "Subnet group for database servers"
    depends_on = ["aws_subnet.public"]
    # XXX can we make this include all AZs automatically?
    subnet_ids = ["${aws_subnet.public.0.id}",
                  "${aws_subnet.public.1.id}"]
    tags {
      Name = "${var.sitename}-db"
      Terraform = "true"
    }
}

resource "aws_route53_zone" "private_dns" {
  count = "${var.enable_private_dns_zone ? 1 : 0}"
  name = "${var.sitedomain}"
  vpc {
    vpc_id = "${aws_vpc.default.id}"
  }
  tags { Terraform = "true" }
}


# GLOBAL SECURITY GROUPS

resource "aws_security_group" "ssh_access" {
  name = "${var.sitename}-ssh-access"
  description = "Grant SSH access from restricted CIDR ranges"
  vpc_id = "${aws_vpc.default.id}"
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["${split(",", var.ssh_sources)}"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags { 
    Name = "${var.sitename}-ssh-access" 
    Terraform = "true"
  }
}

# ELB and HAProxy security groups are up here in the global file
# since putting them inside a frontend module would create dependency cycle problems.

resource "aws_security_group" "fe_elb" {
  count = "${var.enable_frontend_security_groups ? 1 : 0}"
  name = "${var.sitename}-fe-elb"
  description = "Front-end public ELB security group"
  vpc_id = "${aws_vpc.default.id}"
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags { 
    Name = "${var.sitename}-fe-elb" 
    Terraform = "true"
  }
}

resource "aws_security_group" "fe_haproxy" {
  count = "${var.enable_frontend_security_groups ? 1 : 0}"
  name = "${var.sitename}-fe-haproxy"
  description = "Front-end HAProxy behind the public ELB"
  vpc_id = "${aws_vpc.default.id}"
  tags { 
    Name = "${var.sitename}-fe-haproxy" 
    Terraform = "true"
  }
}
resource "aws_security_group_rule" "fe_haproxy_egress" {
  count = "${var.enable_frontend_security_groups ? 1 : 0}"
  security_group_id = "${aws_security_group.fe_haproxy.id}"
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "fe_haproxy_ingress_elb" {
  count = "${var.enable_frontend_security_groups ? 1 : 0}"
  security_group_id = "${aws_security_group.fe_haproxy.id}"
  type = "ingress"
  # HTTP redirect on 80
  # normal post-SSL HTTP traffic on 81
  # 82 kept open for ELB health check
  from_port = 80
  to_port   = 82
  protocol  = "tcp"
  source_security_group_id = "${aws_security_group.fe_elb.id}"
}
resource "aws_security_group_rule" "fe_haproxy_ingress_stats_ssh" {
  count = "${var.enable_frontend_security_groups ? 1 : 0}"
  security_group_id = "${aws_security_group.fe_haproxy.id}"
  type = "ingress"
  from_port = 1936
  to_port   = 1936
  protocol  = "tcp"
  cidr_blocks = ["${split(",", var.ssh_sources)}"]
}

# For running Lambdas in the VPC, we need to create a private subnet,
# since this is the only way to grant them internet accesss.

# Private VPC subnets dedicated to Lambdas
resource "aws_subnet" "lambda" {
  vpc_id = "${aws_vpc.default.id}"
  count = "${var.enable_lambda_subnets ? length(var.azlist) : 0}"
  cidr_block = "${lookup(var.lambda_subnet_cidrs, var.azlist[count.index])}"
  availability_zone = "${var.azlist[count.index]}"
  depends_on = ["aws_internet_gateway.default"]
  tags = "${
    map(
      "Name", "${var.sitename}-lambda-${var.azlist[count.index]}",
      "Terraform", "true"
      )
  }"
  lifecycle = { create_before_destroy = true }
}

# NAT Gateways for Lambda subnets. These exist in the corresponding public subnet.
# And could be shared with any other services that require NAT gateways.

resource "aws_eip" "nat_gw" {
  count = "${var.enable_lambda_subnets ? length(var.azlist) : 0}"
  vpc = true
}
resource "aws_nat_gateway" "gw" {
  count = "${var.enable_lambda_subnets ? length(var.azlist) : 0}"
  allocation_id = "${element(aws_eip.nat_gw.*.id, count.index)}"
  # note: these belong in PUBLIC subnets
  subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
  tags = "${
    map(
      "Name", "${var.sitename}-ngw-${var.azlist[count.index]}",
      "Terraform", "true"
      )
  }"
  depends_on = ["aws_internet_gateway.default"]
}
# Route table to link Lambda subnets to NAT gateways for outgoing traffic
resource "aws_route_table" "lambda_subnet_gw" {
  count = "${var.enable_lambda_subnets ? length(var.azlist) : 0}"
  vpc_id = "${aws_vpc.default.id}"
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.gw.*.id, count.index)}"
  }
  tags {
    Name = "${var.sitename}-lambda-${var.azlist[count.index]}",
  }
}
resource "aws_route_table_association" "lambda_subnet_gw" {
  count = "${var.enable_lambda_subnets ? length(var.azlist) : 0}"
  subnet_id = "${element(aws_subnet.lambda.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.lambda_subnet_gw.*.id, count.index)}"
}
