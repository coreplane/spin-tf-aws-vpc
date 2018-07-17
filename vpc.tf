# VPC setup

resource "aws_vpc" "default" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  tags {
    Name = "${var.sitename}"
    Terraform = "true"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
  tags { Terraform = "true" }
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.default.id}"
  count = "${length(var.azlist)}"
  cidr_block = "${lookup(var.az_subnet_cidrs, var.azlist[count.index])}"
  availability_zone = "${var.azlist[count.index]}"
  map_public_ip_on_launch = true
  depends_on = ["aws_internet_gateway.default"]
  tags {
    Name = "${var.sitename}-public-${var.azlist[count.index]}"
    Terraform = "true"
  }
  lifecycle = { create_before_destroy = true }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }
  tags { Terraform = "true" }
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
  name = "${var.sitedomain}"
  vpc_id = "${aws_vpc.default.id}"
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
  name = "${var.sitename}-fe-haproxy"
  description = "Front-end HAProxy behind the public ELB"
  vpc_id = "${aws_vpc.default.id}"
  tags { 
    Name = "${var.sitename}-fe-haproxy" 
    Terraform = "true"
  }
}
resource "aws_security_group_rule" "fe_haproxy_egress" {
  security_group_id = "${aws_security_group.fe_haproxy.id}"
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "fe_haproxy_ingress_elb" {
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
  security_group_id = "${aws_security_group.fe_haproxy.id}"
  type = "ingress"
  from_port = 1936
  to_port   = 1936
  protocol  = "tcp"
  cidr_blocks = ["${split(",", var.ssh_sources)}"]
}