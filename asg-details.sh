ec2_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
ec2_instance_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
asg_name=$(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 | jq --raw-output --arg inst "${ec2_instance_id}" '.AutoScalingGroups | map(select(.Instances[] | .InstanceId | contains($inst))) | .[].AutoScalingGroupName')

> /tmp/instance.details

counter=0
for ids in `/usr/local/bin/aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.InstanceId)[]'`; do echo "etcd_id_${counter}: $ids" >> /tmp/instance.details; counter=$(( counter + 1 )); done

counter=0
for ips in `/usr/local/bin/aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.NetworkInterfaces[].PrivateIpAddress)[]'`; do echo "etcd_ip_$counter: $ips" >> /tmp/instance.details; counter=$(( counter + 1 )); done

counter=0
for hnames in `/usr/local/bin/aws ec2 describe-instances --region eu-west-2 --instance-ids $(/usr/local/bin/aws autoscaling describe-auto-scaling-groups --region eu-west-2 --auto-scaling-group-name $asg_name | jq .AutoScalingGroups[0].Instances[].InstanceId | xargs) | jq -r '.Reservations[].Instances | map(.NetworkInterfaces[].PrivateDnsName)[]' | sed 's/.eu-west-2.compute.internal//g'`; do echo "etcd_hname_$counter: $hnames" >> /tmp/instance.details; counter=$(( counter + 1 )); done