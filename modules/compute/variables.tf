variable "template_name" {}

variable "common_tags" {
  type        = "list"
  description = "Default Tags"
}

variable "instance_type" {}
variable "master_asg_count" {}
variable "master_name" {}
variable "master_minsize" {}
variable "master_maxsize" {}

variable "master_tags" {
  type  = "list"
  description = "Tags for Master Nodes"
}

variable "etcd_asg_count" {}
variable "etcd_name" {}
variable "etcd_minsize" {}
variable "etcd_maxsize" {}

variable "etcd_tags" {
  type  = "list"
  description = "Tags for ETCD Nodes"
}

variable "worker_asg_count" {}
variable "worker_name" {}
variable "worker_minsize" {}
variable "worker_maxsize" {}

variable "worker_tags" {
  type        = "list"
  description = "Tags for Worker Nodes"
}

variable "grace_period" {}

variable "subnet_id" {
  type = "list"
}

variable "key_name" {}
#variable "image_id" {}
variable "image_name" {}
variable "cluster_sg" {}
variable "vpc_id" {}

variable "default_tags" {
  type = "map"
}

variable "zone_id" {
  default              = "Z2YYO2DMBI4CR6"
}

variable "hosted_zone"{
  default          = "myorg.co.uk"
}

variable "iam_role_name" {
  default = ""
}

variable "efs_id" {
  default = ""
}

variable "etcd_cnf_file" {
  default = "/etc/etcd/etcd.conf"
}

variable "etcd_cert_path" {
  default = "/etc/etcd/pki"
}

variable "kube_cert_path" {
  default = "/etc/kubernetes/pki"
}
