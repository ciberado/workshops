#!/bin/bash

export AWS_DEFAULT_REGION=us-east-1

export OLD_SERVER_PORT=8080
export SERVER_PORT=80

echo Removing old security group rule ($OLD_SERVER_PORT).
aws ec2 revoke-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port $OLD_SERVER_PORT \
    --cidr 0.0.0.0/0


echo Authorizing new security gruop rule ($SERVER_PORT)
aws ec2 authorize-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port $SERVER_PORT \
    --cidr 0.0.0.0/0

ORIGINAL_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=PokemonServer" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

echo Terminating the original instance ID is $ORIGINAL_INSTANCE_ID.
aws ec2 terminate-instances --instance-ids $ORIGINAL_INSTANCE_ID


echo Starting a new instance.
aws ec2 run-instances \
    --subnet-id $SUBNETID\
    --image-id $AMI \
    --security-group-ids $SG \
    --instance-type t3.medium \
    --block-device-mapping DeviceName=/dev/sda1,Ebs={VolumeSize=8} \
    --user-data file://user-data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=pokemon-server},{Key=App,Value=Pokemon}]" |
    > /dev/null

IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=pokemon-server" \
	--filters "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text)
echo Your application is at http://$IP:$SERVER_PORT
