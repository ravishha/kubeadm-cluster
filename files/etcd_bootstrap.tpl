#cloud-boothook
#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/etcd-log.out 2>&1

###################################################
# Configuration Files for creating ETCD Peer Certs.
###################################################
function server_cert_conf_files() {
  cat > ${cert_path}/etcd-$ec2_instance_ip-ext.cnf <<- EOF
  [ server ]
  authorityKeyIdentifier=keyid,issuer
  subjectKeyIdentifier=hash
  basicConstraints=CA:FALSE
  keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
  extendedKeyUsage = serverAuth, clientAuth
  subjectAltName = @alt_names

  [ alt_names ]
  IP.1 = "$ec2_instance_ip"
  IP.2 = "127.0.0.1"
  IP.3 = "0:0:0:0:0:0:0:1"
  IP.4 = "0.0.0.0"
EOF

cat > /etc/etcd/pki/etcd-$ec2_instance_ip-cert.cnf <<- EOF
default_bit = 4096
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
countryName             = UK
emailAddress     	= myorg@myorg.co.uk 
organizationName        = MyOrg
commonName              = etcd-ca
EOF

}

#######################################
# Mounts efs volume.
#######################################
function mount_efs_volume() {
  efs_id=$1
  sudo mount -t efs $efs_id:/ /shared_data
  sudo chmod 777 /shared_data
}

#######################################
# Checks if efs mount is available
#
# Returns:
#   1 if efs mount is available, 0 otherwise
#######################################
function check_efs_mount() {
  efs_id=$1
  for i in $(seq 1 50); do
    check_efs_mount=$(df -h |grep "$efs_id")
    exit_code=$?

    if [[ $exit_code == 0 ]]; then
      return 1
    else
      sleep 10s
      echo "The EFS mount still not available"
    fi
  done

  return 0

if [ $EFS_MOUNTED -eq 1 ]; then
  server_cert_conf_files
fi

}


function generate_etcd_peer_certificate() {
	cert_path=$1
	SERVER_KEY=$2
	SERVER_CSR=$3
	SERVER_CRT=$4
	SERVER_CONF=$5
	SERVER_EXT=$6
	CA_KEY=$7
	CA_CRT=$8
	OPENSSL_CMD=$9
	ETCDCTL_CMD=$10
	COMMON_NAME=$11

    echo "Generating server private key"
    $OPENSSL_CMD genrsa -out $SERVER_KEY 4096 2>/dev/null
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_KEY" && exit 1

    echo "Generating certificate signing request for server"
    $OPENSSL_CMD req -new -key $SERVER_KEY -out $SERVER_CSR -config $SERVER_CONF #2>/dev/null
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_CSR" && exit 1

    echo "Generating RootCA signed server certificate"
    $OPENSSL_CMD x509 -req -in $SERVER_CSR -CA $CA_CRT -CAkey $CA_KEY -out $SERVER_CRT -CAcreateserial -days 365 -sha512 -extfile $SERVER_EXT -extensions server 2>/dev/null
    [[ $? -ne 0 ]] && echo "ERROR: Failed to generate $SERVER_CRT" && exit 1

    echo "Verifying the server certificate against RootCA"
    $OPENSSL_CMD verify -CAfile $CA_CRT $SERVER_CRT >/dev/null 2>&1
    [[ $? -ne 0 ]] && echo "ERROR: Failed to verify $SERVER_CRT against $CA_CRT" && exit 1

    sudo chmod 755 /etc/etcd/pki/*.crt
    sudo chmod 755 /etc/etcd/pki/*.key
}


function etcd_server_conf_file() {

	ec2_instance_ip=$1
	etcd_peer_names=$2
	etcd_peer_ips=$3

sudo cat > /etc/etcd/etcd.conf <<- EOF
ETCD_NAME="$ec2_instance_name"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://$ec2_instance_ip:2380"
ETCD_LISTEN_PEER_URLS="https://$ec2_instance_ip:2380"
ETCD_LISTEN_CLIENT_URLS="https://$ec2_instance_ip:2379,https://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="https://$ec2_instance_ip:2379"
ETCD_DATA_DIR=/var/lib/etcd/data
ETCD_WAL_DIR=/var/lib/etcd/wal
ETCD_INITIAL_CLUSTER_TOKEN=cdos-etcd-cluster
ETCD_INITIAL_CLUSTER="$${etcd_peer_names[0]}=https://$${etcd_peer_ips[0]}:2380,$${etcd_peer_names[1]}=https://$${etcd_peer_ips[1]}:2380,$${etcd_peer_names[2]}=https://$${etcd_peer_ips[2]}:2380"
ETCD_LOG_LEVEL=debug
GOMAXPROCS=2
ETCD_INITIAL_CLUSTER_STATE=existing
ETCD_TRUSTED_CA_FILE="/etc/etcd/pki/ca.crt"
ETCD_CERT_FILE="/etc/etcd/pki/etcd-$ec2_instance_ip.crt"
ETCD_KEY_FILE="/etc/etcd/pki/etcd-$ec2_instance_ip.key"
ETCD_PEER_TRUSTED_CA_FILE="/etc/etcd/pki/ca.crt"
ETCD_PEER_CERT_FILE="/etc/etcd/pki/etcd-$ec2_instance_ip.crt"
ETCD_PEER_KEY_FILE="/etc/etcd/pki/etcd-$ec2_instance_ip.key"
EOF

sudo cat > /etc/systemd/system/etcd.service <<- EOF
[Unit]
Description=Etcd Server

[Service]
Type=notify
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd

Restart=always
RestartSec=10s
LimitNOFILE=40000
TimeoutStartSec=0


[Install]
WantedBy=multi-user.target
EOF
}

# Main Function

[ -d /etc/etcd ] && echo "/etc/etcd Directory Exists" || sudo mkdir /etc/etcd
[ -d /etc/etcd/pki ] && echo "/etc/etcd/pki Directory Exists" || sudo mkdir /etc/etcd/pki
[ -d /shared_data ] && echo "/shared_data Directory Exists" || sudo mkdir /shared_data

efs_id="${efs_id}"

ec2_instance_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Instance IP is $ec2_instance_ip"

cert_path="/etc/etcd/pki"
SERVER_KEY="$cert_path/etcd-$ec2_instance_ip.key"
SERVER_CSR="$cert_path/etcd-$ec2_instance_ip.csr"
SERVER_CRT="$cert_path/etcd-$ec2_instance_ip.crt"
SERVER_CONF="$cert_path/etcd-$ec2_instance_ip-cert.cnf"
SERVER_EXT="$cert_path/etcd-$ec2_instance_ip-ext.cnf"
COMMON_NAME="etcd-client"

ec2_instance_name=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname | sed 's\.corp.hmrc.gov.uk\\g')

echo "Instance Name is $ec2_instance_name"

ec2_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

echo "Instance ID is $ec2_instance_id"

asg_name=$(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 | jq --raw-output --arg inst "$ec2_instance_id" '.AutoScalingGroups | map(select(.Instances[] | .InstanceId | contains($inst))) | .[].AutoScalingGroupName')

echo "The ASG Name is $asg_name"

etcd_peer_ips=($(aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.NetworkInterfaces[].PrivateIpAddress)[]'))

echo "The ETCD Peer IPs are:- $(for x in $${etcd_peer_ips[@]}; do echo $x; done)"

etcd_peer_names=($(aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.NetworkInterfaces[].PrivateDnsName)[]' | sed 's/.eu-west-2.compute.internal//g'))

echo "The ETCD Peer Names are:- $(for x in $${etcd_peer_names[@]}; do echo $x; done)"

etcd_peer_urls=$(/usr/local/bin/aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map("https://" + .NetworkInterfaces[].PrivateIpAddress + ":2379")[]')

echo "The ETCD Peer URLs are $etcd_peer_urls"

echo "Mount the NFS shared volume to copy CA and Peer ETCD Certs and Keys"
mount_efs_volume $efs_id

echo "Checking if the NFS Mount is properly mounted"
check_efs_mount $efs_id

echo "Copying the etcd CA certs to sign the member cert and key"

if [ -d /etc/etcd ] && [ -d /shared_data ]; then 
	sudo cp /shared_data/etcd/ca* /etc/etcd/pki/
fi

# Copy the etcd existing members certs and keys to access the endpoints
if [ -d /etc/etcd/pki ] && [ -d /shared_data ]; then
	sudo cp /shared_data/etcd/etcd* /etc/etcd/pki/
fi

server_cert_conf_files $cert_path $ec2_instance_ip

etcd_server_conf_file $ec2_instance_ip $etcd_peer_names $etcd_peer_ips

CA_KEY="$cert_path/ca.key"
CA_CRT="$cert_path/ca.crt"
OPENSSL_CMD="/usr/bin/openssl"

SERVER_CRT="$cert_path/etcd-$ec2_instance_ip.crt"
SERVER_KEY="$cert_path/etcd-$ec2_instance_ip.key"

if [ ! -f /etc/etcd/pki/etcd-$ec2_instance_ip.crt ]; then

	echo "Generating the certs and keys for the new peer"
	
	generate_etcd_peer_certificate $cert_path $SERVER_KEY $SERVER_CSR $SERVER_CRT $SERVER_CONF $SERVER_EXT $CA_KEY $CA_CRT $OPENSSL_CMD $ETCDCTL_CMD $COMMON_NAME

fi

ETCDCTL_CMD="/usr/local/bin/etcdctl --cacert $CA_CRT --cert $SERVER_CRT --key $SERVER_KEY"
CURL_CMD="curl -s -o /dev/null -I -w "%%{http_code}" --cacert $CA_CRT --cert $SERVER_CRT --key $SERVER_KEY"

for EP in $etcd_peer_urls
do	

	if [ "$($CURL_CMD $EP/metrics)" == "200" ]; then
		ETCDCTL_ENDPOINTS="--endpoints $EP"
		echo "Checking for a healthy endpoint to access the cluster using one"
		echo "The Chosen Endpoint is $ETCDCTL_ENDPOINTS" 
	fi
done

if [ "$ETCDCTL_ENDPOINTS" != "" ]; then
  
  echo "Checking if all the existing ETCD members are part of the ASG"

  for IP in $($ETCDCTL_CMD $ETCDCTL_ENDPOINTS member list | awk '{print $4}' | sed 's/https:\/\///g' | sed 's/:2380,//g')
  do
	  echo "$etcd_peer_urls" | grep $IP && bad_peer_ip="" || bad_peer_ip="$IP"

	  if [ "$bad_peer_ip" != "" ]; then
	  
		echo "Removing the failed ETCD peer $IP"
	  
		bad_peer_id="$($ETCDCTL_CMD $ETCDCTL_ENDPOINTS member list | grep $IP | awk '{print $1}' | sed 's\,\\g')"

          	echo "List the current peers in the cluster"
          	$ETCDCTL_CMD $ETCDCTL_ENDPOINTS member list
	  
		echo "Remove the failed peer from the cluster"
         	$ETCDCTL_CMD $ETCDCTL_ENDPOINTS member remove $bad_peer_id

	  	echo "List of active peers in the cluster"
         	$ETCDCTL_CMD $ETCDCTL_ENDPOINTS member list

  	fi
  done

  #Check if the existing members are part of the ASG and add them if it is not
  is_peer_present=$($ETCDCTL_CMD $ETCDCTL_ENDPOINTS member list | grep $ec2_instance_ip | awk '{print $4}' | sed 's/https:\/\///g' | sed 's/:2380,//g')

  if [ "$is_peer_present" == "" ]; then
     echo "Make sure to remove any remnants of previous etcd data:"
	[ -d /var/lib/etcd/data ] && echo "/var/lib/etcd/data Directory Removed" || sudo rm -r /var/lib/etcd/data
	[ -d /var/lib/etcd/wal ] && echo "/var/lib/etcd/wal Directory Removed" || sudo rm -r /var/lib/etcd/wal
    $ETCDCTL_CMD $ETCDCTL_ENDPOINTS member add $ec2_instance_name --peer-urls="https://$ec2_instance_ip:2380"
    systemctl stop etcd
    systemctl daemon-reload
    systemctl start etcd
    systemctl enable etcd
    sudo cp $cert_path/etcd-$ec2_instance_ip.crt /shared_data/etcd
    sudo cp $cert_path/etcd-$ec2_instance_ip.key /shared_data/etcd
  else
	  echo "The nodes is already part of the ETCD Cluster"
  fi

  [[ $(findmnt -M /shared_data) ]] && sudo umount /shared_data
else
   echo "Please Start a instantiate a new ETCD cluster using Ansible if you need one"
fi
