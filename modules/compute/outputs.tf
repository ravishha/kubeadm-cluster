output "lb_dns_name" {
value = "${aws_elb.kube_api_elb.dns_name}"
}

output "security_group_name" {
value = "${aws_security_group.cluster.arn}"
}