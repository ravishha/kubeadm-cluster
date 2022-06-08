provider "aws" {
  region = "${var.region}"
}

#############COMPUTE RESOURCE##############
module "kdm_cluster" {
  source           = "./modules/compute"
  template_name    = "${local.template_name}"
  common_tags      = "${local.shared_tags}"
  instance_type    = "${local.instance_type}"
  master_asg_count = "${local.master_asg_count}"
  master_name      = "${local.master_name}"
  master_minsize   = "${local.master_minsize}"
  master_maxsize   = "${local.master_maxsize}"
  master_tags      = "${local.master_tags}"
  
  etcd_asg_count = "${local.etcd_asg_count}"
  etcd_name      = "${local.etcd_name}"
  etcd_minsize   = "${local.etcd_minsize}"
  etcd_maxsize   = "${local.etcd_maxsize}"
  etcd_tags      = "${local.etcd_tags}"

  worker_asg_count = "${local.worker_asg_count}"
  worker_name      = "${local.worker_name}"
  worker_minsize   = "${local.worker_minsize}"
  worker_maxsize   = "${local.worker_maxsize}"
  worker_tags      = "${local.worker_tags}"
  grace_period     = "${local.grace_period}"
  subnet_id        = "${local.subnet_id}"
  key_name         = "${local.ssh_key_name}"
  image_name         = "${local.image_name}"
  cluster_sg       = "${local.security_group_name}"
  vpc_id           = "${local.vpc_id}"
  default_tags     = "${local.default_cluster_tags}"
}
