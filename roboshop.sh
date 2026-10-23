#!/bin/bash

##############################################################
# RoboShop: create EC2 instances + update Route 53 records
# Usage: bash roboshop.sh mongodb redis mysql rabbitmq catalogue
##############################################################

ami_id="ami-0055977a6e828a4f4"        # Redhat-9-DevOps-Practice
instance_type="t3.micro"
hosted_zone_id="Z0720368AL7KSN1O4AZ2"
domain_name="abhignadevops.store"

for instance in $@
do
    echo "Creating instance: $instance"

    instance_id=$(aws ec2 run-instances \
            --image-id $ami_id \
            --instance-type $instance_type \
            --security-groups "roboshop-common" "roboshop-$instance" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query 'Instances[0].InstanceId' \
            --output text
    )

    echo "$instance ID: $instance_id"

    # wait until running, so the IP is ready
    aws ec2 wait instance-running --instance-ids $instance_id

    if [ $instance != "frontend" ]; then
        IP=$( aws ec2 describe-instances --instance-ids $instance_id \
            --query 'Reservations[].Instances[].PrivateIpAddress' --output text
        )
        r53_record_name="$instance.$domain_name"
    else
        IP=$( aws ec2 describe-instances --instance-ids $instance_id \
            --query 'Reservations[].Instances[].PublicIpAddress' --output text
        )
        r53_record_name="$domain_name"
    fi

    echo "$instance IP: $IP"

    # update R53 record
    # '...'$var'...' -> close the single quote around each variable so bash replaces it

    aws route53 change-resource-record-sets \
    --hosted-zone-id $hosted_zone_id \
    --change-batch '{
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                "Name": "'$r53_record_name'",
                "Type": "A",
                "TTL": 1,
                "ResourceRecords": [{"Value": "'$IP'"}]
                }
            }
        ]
    }'

    echo "DNS updated: $r53_record_name -> $IP"
done
