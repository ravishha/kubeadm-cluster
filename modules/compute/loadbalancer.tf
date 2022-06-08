###########################################
# Application Load Balancer - kube_api
###########################################

# resource "aws_lb" "kube_api_alb" {
#  name                     	= "${var.template_name}-alb"
#  security_groups           	= ["${aws_security_group.cluster.id}"]
#  subnets                   	= "${var.subnet_id}"
#  internal               	= true
#  load_balancer_type		= "application"
#  enable_deletion_protection	= false
#  tags                   	= "${var.common_tags}"
#}


#resource "aws_lb_listener" "kube_api_listener" {
#  load_balancer_arn = "${aws_lb.kube_api_alb.arn}"
#  port      = 6443
#
#  default_action {
#    type             = "forward"
#    target_group_arn = "${aws_lb_target_group.kube_api_target_group.arn}"
#  }
#
#  depends_on = [ "aws_lb.kube_api_alb" ]
#
#}


#resource "aws_lb_target_group" "kube_api_target_group" {
#  port     = 6443
#  protocol = "HTTPS"
#  vpc_id   = "${var.vpc_id}"
#
#  depends_on = [
#    "aws_lb.kube_api_alb"
#  ]
#}

#resource "aws_autoscaling_attachment" "kube_api_asg_attachment" {
#  autoscaling_group_name = "${aws_autoscaling_group.master.name}"
#  alb_target_group_arn   = "${aws_lb_target_group.kube_api_target_group.arn}"
#  depends_on = [
#    "aws_lb.kube_api_alb", 
#    "aws_lb_target_group.kube_api_target_group"
#  ]
#}

resource "aws_elb" "kube_api_elb" {
  name                     	= "${var.template_name}-alb"
  security_groups           	= ["${aws_security_group.cluster.id}"]
  subnets                   	= "${var.subnet_id}"
  internal               	    = true

listener {
  instance_port         = 6443
  instance_protocol     = "TCP"
  lb_port               = 6443
  lb_protocol           = "TCP"
}

listener {
  instance_port         = 2379
  instance_protocol     = "TCP"
  lb_port               = 2379
  lb_protocol           = "TCP"
}

health_check {
  target                = "SSL:6443"
  healthy_threshold     = 2
  unhealthy_threshold   = 2
  interval              = 10
  timeout               = 5
}

cross_zone_load_balancing = true
idle_timeout              = 300

tags                   	= "${var.common_tags}"

}

resource "aws_route53_record" "swarm_elb_cname_vault" {
  zone_id = "${var.zone_id}"
  name    = "cds-kube.${var.hosted_zone}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${aws_elb.kube_api_elb.dns_name}"]
  depends_on = ["aws_elb.kube_api_elb"]
}

resource "aws_autoscaling_attachment" "kube_api_asg_attachment" {
  autoscaling_group_name = "${aws_autoscaling_group.master.name}"
  elb   = "${aws_elb.kube_api_elb.id}"
  depends_on = [
    "aws_elb.kube_api_elb", 
    "aws_autoscaling_group.master"
  ]
}