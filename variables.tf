variable "sitename" {}
variable "sitedomain" {}
variable "ssh_sources" {}

variable "vpc_cidr" {
  description = "CIDR for whole VPC"
  default = "10.128.0.0/16"
}

variable "azlist" {
  description = "List of AWS availability zones to use, including region prefix"
  type = list(string)
  default = ["us-east-1a","us-east-1c"]
}

variable "az_subnet_cidrs" {
  description = "Dictionary of per-availability-zone subnet CIDRs"
  default = {
    "us-east-1a" = "10.128.0.0/24"
    "us-east-1c" = "10.128.2.0/24"
  }
}

variable "lambda_subnet_cidrs" {
  description = "Dictionary of per-availability-zone CIDRs for private Lambda subnets"
  default = {
    "us-east-1a" = "10.128.30.0/24"
    "us-east-1c" = "10.128.32.0/24"
  }
}

variable "enable_private_dns_zone" {
  description = "Whether to create a Route53 private zone for hosts inside the VPC"
  default = true
}

variable "enable_frontend_security_groups" {
  description = "Whether to create VPC security groups to support front-end ingress"
  default = true
}

variable "enable_lambda_subnets" {
  description = "Whether to create private subnets for running Lambdas. (note: creates NAT Gateways, which incur extra cost)."
  default = false
}

variable "enable_ipv6" {
  description = "Configure subnets to use IPv6"
  default = false
}
