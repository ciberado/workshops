# Imperative management

In the next section of our tutorial, we will be addressing the need to alter the port our server is listening on. We have been using port 8080 up until now, but for our production environment, we want to switch to the default HTTP port, 80. This will allow users to access our application without specifying a port number in their browser.

```bash
export SERVER_PORT=80
```

Before we can switch to port 80, we need to ensure that our AWS security group allows traffic on this port. First, we'll remove the rule that allows traffic on port 8080.

```bash
aws ec2 r«evoke»-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0
```

Next, we'll add a new rule that allows traffic on our new server port (80).

```bash
aws ec2 authorize-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port $SERVER_PORT \
    --cidr 0.0.0.0/0
```

Now we need to update our server startup script to use the new port. We'll create a new script named pokemon.sh that updates the server, installs the necessary software, downloads our application, and starts it on the new port.

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

In order to apply these changes, we need to replace our current server instance. First, we'll identify the instance ID of our current server.

```bash
ORIGINAL_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=PokemonServer" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)
echo The original instance ID is $ORIGINAL_INSTANCE_ID.
```

Next, we'll terminate (delete) the original instance.

```bash
aws ec2 «terminate»-instances --instance-ids $ORIGINAL_INSTANCE_ID
```

Now, we're ready to launch a new instance using our updated startup script.

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

Once our new instance is up and running, we can retrieve its public IP address.

```bash
IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=pokemon-server" \
	--filters "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text)
echo Your application is at http://$IP:$SERVER_PORT
```

Finally, we can test our application by making a request to the server and displaying the name of the returned Pokémon.

```bash
echo And your Pokémon is $(curl -s http://$IP:$SERVER_PORT/ | jq .name -r).
```
