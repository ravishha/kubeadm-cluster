#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1> /var/log/master-log.out 2>&1

#######################################
# Mounts efs volume.
#######################################
function mount_efs_volume() {
  sudo mount -t efs ${efs_id}:/ /shared_data
  sudo chmod 777 /shared_data
}

#######################################
# Checks if efs mount is available
#######################################
function check_efs_mount() {
check_efs_mount=$(df -h |grep "${efs_id}")
exit_code=$?

if [[ $exit_code == 0 ]]; then
	exit_code=0
else
	for i in $(seq 1 50); do
    sleep 10s
    echo "The EFS mount still not available"
    exit_code=1
	done
fi

if [ $exit_code -eq 0 ]; then
  echo "Start Copying the Required Certs and Keys"
fi
}

##############################################################################################################
# Main Function

[ -d /etc/kubernetes/pki ] && echo "/etc/kubernetes/pki Directory Exists" || sudo mkdir /etc/kubernetes/pki
[ -d /etc/kubernetes/pki/etcd ] && echo "/etc/kubernetes/pki/etcd Directory Exists" || sudo mkdir /etc/kubernetes/pki/etcd
[ -d /shared_data ] && echo "/shared_data Directory Exists" || sudo mkdir /shared_data

ec2_instance_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Instance IP is $ec2_instance_ip"

kube_cert_path="/etc/kubernetes/pki"

ec2_instance_name=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname | sed 's\.myorg.co.uk\\g')

echo "Instance Name is $ec2_instance_name"

ec2_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

echo "Instance ID is $ec2_instance_id"

asg_name=$(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 | jq --raw-output --arg inst "$ec2_instance_id" '.AutoScalingGroups | map(select(.Instances[] | .InstanceId | contains($inst))) | .[].AutoScalingGroupName')

echo "The ASG Name is $asg_name"

control_plane_ips=$(aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.NetworkInterfaces[].PrivateIpAddress)[]')

control_plane_names=$(aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.NetworkInterfaces[].PrivateDnsName)[]' | sed 's/.eu-west-2.compute.internal//g')

echo "Mount the NFS shared volume to copy CA and Peer ETCD Certs and Keys"
mount_efs_volume

echo "Checking if the NFS Mount is properly mounted"
check_efs_mount

echo "Copying the certs and keys to sign the member cert and key"

kube_cert_list=("ca.crt" "apiserver-etcd-client.crt" "front-proxy-ca.crt" "front-proxy-client.crt" "sa.pub")
kube_key_list=("ca.key" "apiserver-etcd-client.key" "front-proxy-ca.key" "front-proxy-client.key" "sa.key")
etcd_cert_list=("ca.crt" "ca.key")

if [ -d /etc/kubernetes/pki ] && [ -d /etc/kubernetes/pki/etcd ] && [ -d /shared_data/kubernetes ] && [ -d /shared_data/etcd ]; then
  for certs in $${kube_cert_list[@]}
  do 
    if [ -f /etc/kubernetes/pki/$certs ]; then
      echo "/etc/kubernetes/pki/$certs File Exists"
    else
      sudo cp /shared_data/kubernetes/$certs /etc/kubernetes/pki/
      echo "Copying /shared_data/$certs to /etc/kubernetes/pki/$certs"
    fi  
  done

  for keys in $${kube_key_list[@]}
  do
    if [ -f /etc/kubernetes/pki/$keys ]; then
      echo "/etc/kubernetes/pki/$keys File Exists"
    else
      sudo cp /shared_data/kubernetes/$keys /etc/kubernetes/pki/
      echo "Copying /shared_data/$keys to /etc/kubernetes/pki/$keys"
    fi  
  done
  
  for etcd_files in $${etcd_cert_list[@]}
  do
    if [ -f /etc/kubernetes/pki/etcd/$etcd_files ]; then
      echo "/etc/kubernetes/pki/etcd/$etcd_files File Exists"
    else
      sudo cp /shared_data/etcd/$etcd_files /etc/kubernetes/pki/etcd
      echo "Copying /shared_data/etcd/$etcd_files to /etc/kubernetes/pki/etcd/$etcd_files"
    fi  
  done

if [ -f /shared_data/kubernetes/admin.conf ]; then
  echo "Copying /shared_data/kubernetes/admin.conf to /etc/kubernetes/admin.conf"
  sudo cp /shared_data/kubernetes/admin.conf /etc/kubernetes/
fi  

fi

if [ -f /etc/kubernetes/admin.conf ]; then
  KUBE_CONFIG="/etc/kubernetes/admin.conf"
  echo "Setting the system config"
  echo 1 > /proc/sys/net/ipv4/ip_forward

  echo "Setting variables"
  CA_KEY="$kube_cert_path/ca.key"
  CA_CRT="$kube_cert_path/ca.crt"
  OPENSSL_CMD="/usr/bin/openssl"  
else
  KUBE_CONFIG=""
fi

if [ "$KUBE_CONFIG" != "" ]; then
  KUBECTL_CMD="/bin/kubectl --kubeconfig $KUBE_CONFIG"
  KUBE_MASTERS=$($KUBECTL_CMD get nodes |grep -i master | awk '{print $1}')
else
  KUBE_MASTER=""
fi

if [ "$KUBE_MASTERS" != "" ] && [ "$KUBE_CONFIG" != "" ]; then
  for NAME in $($KUBECTL_CMD get nodes | grep -i master | grep -i notready | awk '{print $1}'| sed 's/worker-//g')
  do
	    echo "$controlplane_ips" | grep $NAME && bad_controlplane_name="" || bad_controlplane_name="$NAME"
    if [ "$bad_controlplane_name" != "" ]; then
		  echo "Removing the failed ControlPlane Node - $NAME"
	  
	    echo "List the current controlplane nodes in the cluster"
        $KUBECTL_CMD get nodes | grep -i master
	  
		  echo "Remove the failed ControlPlane node from the cluster"
        $KUBECTL_CMD delete node $bad_controlplane_name

	    echo "List the current controlplane nodes in the cluster"
        $KUBECTL_CMD get nodes | grep -i master
    fi
  done

  
  echo "Checking if the existing members are part of the ASG and add them if it is not"

  is_node_present=$($KUBECTL_CMD get nodes | grep $ec2_instance_ip | awk '{print $1}' | sed 's/master-//g')

  if [ "$is_node_present" == "" ]; then
    echo "Make sure to remove any remnants of previous etcd data:"
    master_join_command="$(kubeadm token create --print-join-command)"
    kubeadm init phase upload-certs --upload-certs
    $master_join_command --control-plane --node-name "master-$ec2_instance_ip"
  else
	  echo "The nodes are already part of the Kubernetes Controlplane Cluster"
  fi
  [[ $(findmnt -M /shared_data) ]] && sudo umount /shared_data
else
   echo "Please instantiate a new K8s cluster using Ansible if you need one"
fi
