variable "sitename" {}
variable "sitedomain" {}
variable "ssh_sources" {}

variable "vpc_cidr" {
  description = "CIDR for whole VPC"
  default = "10.128.0.0/16"
}

variable "azlist" {
  description = "List of AWS availability zones to use, including region prefix"
  type = "list"
  default = ["us-east-1a","us-east-1c"]
}

variable "az_subnet_cidrs" {
  description = "Dictionary of per-availability-zone subnet CIDRs"
  default = {
    "us-east-1a" = "10.128.0.0/24"
    "us-east-1c" = "10.128.2.0/24"
  }
}
