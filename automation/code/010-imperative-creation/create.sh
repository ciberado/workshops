#!/bin/bash

export AWS_DEFAULT_REGION=us-east-1

export SERVER_PORT=8080

DEFAULTVPCID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" --output text)
  
echo Your VPC is $DEFAULTVPCID.

SUBNETID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULTVPCID" \
  --query "Subnets[0].SubnetId" \
  --output text)
  
echo Your subnet is $SUBNETID.

SG=$(aws ec2 create-security-group \
    --group-name PokemonSG\
    --description "The security group of the application." \
    --vpc-id $DEFAULTVPCID\
    --query 'GroupId' \
    --output text)
echo The security group is $SG.

aws ec2 authorize-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port $SERVER_PORT \
    --cidr 0.0.0.0/0


AMI=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*' 'Name=state,Values=available' \
    --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' \
    --output text)
echo The AMI is going to be $AMI.

aws ec2 run-instances \
    --subnet-id $SUBNETID\
    --image-id $AMI \
    --security-group-ids $SG \
    --instance-type t2.medium \
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

