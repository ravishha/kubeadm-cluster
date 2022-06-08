data "template_file" "etcd_bootstrap" {
  template = "${file("./files/etcd_bootstrap.tpl")}"

  vars = {
    efs_id           = "${var.efs_id}"
    cert_path        = "${var.etcd_cert_path}"
    etcd_cnf_file    = "${var.etcd_cnf_file}"
  }
}

data "aws_ami" "cluster_ami" {
  most_recent      = true
  owners           = ["self"]

  filter {
    name   = "name"
    values = ["${var.image_name}"]
  }
}

data "template_file" "master_bootstrap" {
  template = "${file("./files/master_bootstrap.tpl")}"

  vars = {
    efs_id           = "${var.efs_id}"
    kube_cert_path   = "${var.kube_cert_path}"
  }
}

data "template_file" "worker_bootstrap" {
  template = "${file("./files/worker_bootstrap.tpl")}"

  vars = {
    efs_id           = "${var.efs_id}"
    kube_cert_path        = "${var.kube_cert_path}"
  }
}

data "aws_availability_zones" "all" {}

resource "aws_launch_template" "etcd" {
  name                   = "${var.template_name}-etcd"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
#  image_id               = "${var.image_id}"
  image_id               = "${data.aws_ami.cluster_ami.id}"
  vpc_security_group_ids = ["${aws_security_group.cluster.id}"]
  user_data	           = "${base64encode(data.template_file.etcd_bootstrap.rendered)}"
  iam_instance_profile   = {
    name = "CDOS_CI_EC2_Role"
  }
  tags                   = "${var.common_tags}"
  block_device_mappings {
      device_name = "/dev/sda1"
      ebs {
          volume_size = 40
      }
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "master" {
  name                   = "${var.template_name}-master"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
#  image_id               = "${var.image_id}"
  image_id               = "${data.aws_ami.cluster_ami.id}"
  vpc_security_group_ids = ["${aws_security_group.cluster.id}"]
  user_data	           = "${base64encode(data.template_file.master_bootstrap.rendered)}"
  iam_instance_profile   = {
    name = "CDOS_CI_EC2_Role"
  }
  tags                   = "${var.common_tags}"
  block_device_mappings {
      device_name = "/dev/sda1"
      ebs {
          volume_size = 40
      }
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "worker" {
  name                   = "${var.template_name}-worker"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
#  image_id               = "${var.image_id}"
  image_id               = "${data.aws_ami.cluster_ami.id}"
  vpc_security_group_ids = ["${aws_security_group.cluster.id}"]
  user_data	           = "${base64encode(data.template_file.worker_bootstrap.rendered)}"
  iam_instance_profile   = {
    name = "CDOS_CI_EC2_Role"
  }
  tags                   = "${var.common_tags}"
  block_device_mappings {
      device_name = "/dev/sda1"
      ebs {
          volume_size = 40
      }
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "master" {
  count                     = "${var.master_asg_count}"
  name                      = "${var.master_name}"
  min_size                  = "${var.master_minsize}"
  max_size                  = "${var.master_maxsize}"
  health_check_grace_period = "${var.grace_period}"
  vpc_zone_identifier       = ["${element("${var.subnet_id}", 0)}", "${element("${var.subnet_id}", 1)}", "${element("${var.subnet_id}", 2)}"]

  launch_template = {
    id      = "${aws_launch_template.master.id}"
    version = "$Latest"
  }
  
  tags = [
     "${concat(var.common_tags, var.master_tags)}"
  ]
}

resource "aws_autoscaling_group" "etcd" {
  count                     = "${var.etcd_asg_count}"
  name                      = "${var.etcd_name}"
  min_size                  = "${var.etcd_minsize}"
  max_size                  = "${var.etcd_maxsize}"
  health_check_grace_period = "${var.grace_period}"
  vpc_zone_identifier       = ["${element("${var.subnet_id}", 0)}", "${element("${var.subnet_id}", 1)}", "${element("${var.subnet_id}", 2)}"]

  launch_template = {
    id      = "${aws_launch_template.etcd.id}"
    version = "$Latest"
  }
  
  tags = [
     "${concat(var.common_tags, var.etcd_tags)}"
  ]
}


resource "aws_autoscaling_group" "worker" {
  count                     = "${var.worker_asg_count}"
  name                      = "${var.worker_name}"
  min_size                  = "${var.worker_minsize}"
  max_size                  = "${var.worker_maxsize}"
  health_check_grace_period = "${var.grace_period}"
  vpc_zone_identifier       = ["${element("${var.subnet_id}", 0)}", "${element("${var.subnet_id}", 1)}", "${element("${var.subnet_id}", 2)}"]

  launch_template = {
    id      = "${aws_launch_template.worker.id}"
    version = "$Latest"
  }

  tags = [ "${concat(var.common_tags, var.worker_tags)}" ]
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_sg}"
  description = "Security group for kubeadm cluster"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${var.common_tags}"
}