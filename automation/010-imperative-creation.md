# Imperative automation

In our quest to provide a fun and interactive Pokémon experience, we're going to set up an AWS environment to host our Pokémon application. The first few lines of code are dedicated to configuring this environment. We'll be using AWS CLI, so we start by checking the AWS version installed on our system. Then, we define the AWS region where we'll be deploying our resources and set a unique prefix for our resources.

## Environment configuration

```bash
aws version
```

```bash
export AWS_DEFAULT_REGION=us-east-1
```

```bash
export MYPREFIX=<your very unique prefix>
```

## Network information gathering

Next, we're going to manually deploy our Pokémon application. We start by creating a new directory for our project and setting the server port to 8080. We then fetch the ID of the default Virtual Private Cloud (VPC) in our AWS account, which is a virtual network dedicated to our AWS resources. We also fetch the ID of a subnet, which is a range of IP addresses in our VPC.

```bash
cd
mkdir pokemon-imperative
cd pokemon-bash
```

```bash
export SERVER_PORT=8080
```

```bash
DEFAULTVPCID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" --output text)
  
echo Your VPC is $DEFAULTVPCID.
```

```bash
SUBNETID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULTVPCID" \
  --query "Subnets[0].SubnetId" \
  --output text)
  
echo Your subnet is $SUBNETID.
```

## Firewall configuration

To secure our application, we create a security group in our VPC. This acts as a virtual firewall that controls the traffic for our application. We then add a rule to this security group that allows incoming traffic on our server port from any IP address.

```bash
SG=$(aws ec2 create-security-group \
    --group-name AppSG\
    --description "The security group of the application." \
    --vpc-id $DEFAULTVPCID\
    --query 'GroupId' \
    --output text)
echo The security group is $SG.
```

```bash
aws ec2 authorize-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port $SERVER_PORT \
    --cidr 0.0.0.0/0
```

## Instance state configuration

To prepare for the launch of an EC2 instance, we fetch the ID of the latest Ubuntu 22.04 AMI available. An AMI, or Amazon Machine Image, provides the information required to launch an instance, which is a virtual server in AWS.

```bash
AMI=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*' 'Name=state,Values=available' \
    --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' \
    --output text)
echo The AMI is going to be $AMI.
```

Next, we create a bash script that will be used as user data for our instance. This script updates the system packages, installs AWS CLI and Java Runtime Environment, downloads our Pokémon application, and runs it on our server port.

```bash
cat << EOF > pokemon.sh
#!/bin/sh
 
sudo apt update
sudo apt install awscli openjdk-17-jre-headless -y
wget https://github.com/ciberado/pokemon-java/releases/download/v2.0.0/pokemon-2.0.0.jar
java -jar -Dserver.port=$SERVER_PORT pokemon-2.0.0.jar
EOF
```

```bash
cat pokemon.sh
```

## Server creation

After verifying our bash script, we launch our EC2 instance in the previously defined subnet, using the Ubuntu AMI and the security group we created. We also add a block device mapping to specify that the root volume of the instance has a size of 8 GB. The user data for the instance is the bash script we created, which will be executed upon launch.

```bash
aws ec2 run-instances \
    --subnet-id $SUBNETID\
    --image-id $AMI \
    --security-group-ids $SG \
    --instance-type t3.micro \
    --block-device-mapping DeviceName=/dev/sda1,Ebs={VolumeSize=8} \
    --user-data file://pokemon.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=pokemon-server},{Key=App,Value=Pokemon}]"
```

## Application test

Lastly, we fetch the public IP address of our running instance and print the URL of our application. We then make a GET request to our application and print the name of the Pokémon returned by the application. This concludes our manual deployment of the Pokémon application on AWS.

```bash
IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=pokemon-server" \
	--filters "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text)
echo Your application is at http://$IP:$SERVER_PORT
```

```bash
echo And your Pokémon is $(curl -s http://$IP:$SERVER_PORT/ | jq .name -r).
```
