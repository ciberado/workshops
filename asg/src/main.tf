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


data "aws_ami" "ubuntu_lts" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_launch_template" "nginx" {
  name     = "nginx"
  image_id = data.aws_ami.ubuntu_lts.id

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 8
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<EOF
  #!/bin/bash
  apt-get update -y
  apt-get install -y nginx
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "asgdemo"
    }
  }
  
}

resource "aws_autoscaling_group" "nginx" {
  vpc_zone_identifier = data.aws_subnets.default.ids

  desired_capacity = 50
  max_size         = 50
  min_size         = 0

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
        launch_template_id = aws_launch_template.nginx.id
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

Counting instances:

aws ec2 describe-instances \
  --filter 'Name=tag:Name,Values=asgdemo' \
  --query 'Reservations[*].Instances[*].{Instance:InstanceId,Spot:InstanceLifecycle,Subnet:SubnetId,Type:InstanceType}' \
  --output text \
| cut -f2 \
| sort \
| uniq -c


*/