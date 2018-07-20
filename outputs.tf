output "vpc_id" {
  value = "${aws_vpc.default.id}"
}

output "ready" {
  value = "${join(",",aws_route_table_association.public.*.id)}"
}

output "public_subnet_id0" {
  # work-around for Terraform bug, see http://dexlab.net/pukiwiki/index.php?cmd=read&page=Memo%2FTerraform
#  value = "${aws_subnet.public.0.id}"
  value = "${element(aws_subnet.public.*.id, 0)}"
}
output "public_subnet_id1" {
  # work-around for Terraform bug, see http://dexlab.net/pukiwiki/index.php?cmd=read&page=Memo%2FTerraform
#  value = "${aws_subnet.public.1.id}"
  value = "${element(aws_subnet.public.*.id, 1)}"
}
output "public_subnet_ids" {
  value = "${aws_subnet.public.*.id}"
}

output "db_subnet_group_id" {
  value = "${aws_db_subnet_group.db_subnet_group.id}"
}

output "ssh_access_security_group_id" {
  value = "${aws_security_group.ssh_access.id}"
}

output "fe_elb_security_group_id" {
  value = "${aws_security_group.fe_elb.id}"
}

output "fe_haproxy_security_group_id" {
  value = "${aws_security_group.fe_haproxy.id}"
}

output "private_dns_zone_id" {
  value = "${join(",", aws_route53_zone.private_dns.*.zone_id)}"
}
