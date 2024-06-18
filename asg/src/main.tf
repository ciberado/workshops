provider "aws" {
  region = "eu-west-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "asgdemo_lb" {
  name        = "asgdemo_lb_sg"
  description = "Demo load balancer security group"

  vpc_id = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "asgdemo" {
  name               = "asgdemo-lb"
  internal           = false
  load_balancer_type = "network"
  subnets            = data.aws_subnets.default.ids
  security_groups = [ aws_security_group.asgdemo_lb.id ]
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.asgdemo.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asgdemo.arn
  }
}

resource "aws_lb_target_group" "asgdemo" {
  name     = "asgdemotg"
  port     = 8080
  protocol = "TCP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    interval            = 30
    port                = "traffic-port"
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    protocol            = "TCP"
  }
}

data "aws_ami" "ubuntu_lts" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "asgdemo_app" {
  name        = "asgdemo_app_sg"
  description = "Demo instances security group"

  vpc_id = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.asgdemo_lb.id]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }  
}

resource "aws_launch_template" "asgdemo" {
  name     = "asgdemo_template"
  instance_type = "t3.micro"
  image_id = data.aws_ami.ubuntu_lts.id

  vpc_security_group_ids  = [aws_security_group.asgdemo_app.id]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 8
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<EOF
#!/bin/sh
 
sudo apt update
sudo apt install awscli openjdk-17-jre-headless -y
//wget https://github.com/ciberado/pokemon-java/releases/download/v2.0.0/pokemon-2.0.0.jar
//java -jar pokemon-2.0.0.jar
wget https://github.com/ciberado/pokemon-java/releases/download/v2.0.5/pokemon-2.0.5.jar
java -jar pokemon-2.0.5.jar
EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "asgdemo"
    }
  }
}

resource "aws_autoscaling_group" "asgdemo" {
  name                = "asgdemo_asg"
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [ aws_lb_target_group.asgdemo.arn ]

  desired_capacity = 4
  max_size         = 50
  min_size         = 0

  max_instance_lifetime = 60*60*24*7

  capacity_rebalance = true
  
  mixed_instances_policy {

    instances_distribution {
      // prioritized, lowest-price
      on_demand_allocation_strategy = "prioritized"
      // Minimum number of on-demand/reserved nodes
      on_demand_base_capacity = 2
      // Once that minimum has been granted, percentage of on-demand for
      // the rest of the total capacity
      on_demand_percentage_above_base_capacity = 25
      // lowest-price, capacity-optimized, capacity-optimized-prioritized, price-capacity-optimized
      spot_allocation_strategy = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.asgdemo.id
      }

      override {
        instance_type     = "t3.micro"
        weighted_capacity = "1"
      }

      override {
        instance_type     = "t3.small"
        weighted_capacity = "2"
      }

      override {
        instance_type     = "t3.medium"
        weighted_capacity = "2"
      }
    }
  }
}

/*

Counting instances, aggregating by spot/on-demand:

aws ec2 describe-instances \
  --filter 'Name=tag:Name,Values=asgdemo' "Name=instance-state-name,Values=running"  \
  --query 'Reservations[*].Instances[*].{Instance:InstanceId,Spot:InstanceLifecycle,Subnet:SubnetId,Type:InstanceType}' \
  --output text \
| cut -f2 \
| sort \
| uniq -c

Counting instances, aggregating by subnet:

aws ec2 describe-instances \
  --filter 'Name=tag:Name,Values=asgdemo' "Name=instance-state-name,Values=running"  \
  --query 'Reservations[*].Instances[*].{Instance:InstanceId,Spot:InstanceLifecycle,Subnet:SubnetId,Type:InstanceType}' \
  --output text \
| cut -f3 \
| sort \
| uniq -c

Counting instances, aggregating by instance type:

aws ec2 describe-instances \
  --filter 'Name=tag:Name,Values=asgdemo' "Name=instance-state-name,Values=running"  \
  --query 'Reservations[*].Instances[*].{Instance:InstanceId,Spot:InstanceLifecycle,Subnet:SubnetId,Type:InstanceType}' \
  --output text \
| cut -f4 \
| sort \
| uniq -c

Reviewing application version for each instance:

IPs=$(aws ec2 describe-instances   \
  --filter 'Name=tag:Name,Values=asgdemo' "Name=instance-state-name,Values=running"  \
  --query 'Reservations[*].Instances[*].{IP:PublicIpAddress}'   \
  --output text)

for ip in $IPs
do
  echo Instance $ip: "  " $(curl -H "Accept: text/html" $ip:8080 -s | grep -Po '\d.\d.\d')
done

*/