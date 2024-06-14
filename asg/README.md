[](.coverbg)

![NTT presentation](images/ntt-slides-title.png)

# Auto Scaling Groups
(the less known goodies)

[](.agenda.powerlist)

### Agenda

* ASG configuration
* Maintenance policies
* Lifecycle hooks
* Warm pools
* Instance recycling
* Refreshing instances

[]()

### What is a Launch Template?

It is a resource describing the desired state of a fresh
instance. It is usually used in combination of one or
more Auto Scaling Groups.

```terraform
resource "aws_launch_template" "nginx" {
  name          = "nginx" 
  block_device_mappings {
    ...
    ebs {
      volume_size = 8
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<EOF
  #!/bin/bash
  ...
  EOF
  )
}
```


[]()

## ASG capacity management

[]()

### Mixed fleets

It enhances the ability of the ASG of getting the required instances,
while providing greater spot resiliency. AWS [recommends](https://docs.aws.amazon.com/autoscaling/ec2/userguide/mixed-instances-groups-set-up-overview.html#mixed-instances-group-instance-flexibility) 
using 10 instance types as a best practice!

```terraform
resource "aws_autoscaling_group" "nginx" {
  ...
  mixed_instances_policy {
    launch_template {
      ...
      override {
        instance_type     = "t3.micro"
        weighted_capacity = "1"
      }
      override {
        instance_type     = "t3.small"
        weighted_capacity = "2"
      }
    }
  }
}
```

### Mixed with spot

It is possible in the ASG to determine which percentage of the instances
should be created as spot and which one should be non-spot. This feature
provides an easy way to balance the risk of interruption in smaller fleets.

```terraform
resource "aws_autoscaling_group" "nginx" {
  ...
  mixed_instances_policy {
    instances_distribution {
      on_demand_allocation_strategy = "prioritized"
      on_demand_base_capacity       = 2
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy      = "capacity-optimized"
    }
    ...
  }
}
```

::: Notes

If you set mixed capacity in your ASG, your LT should
not specify any market option in your launch template.


*  `on_demand_allocation_strategy`: `prioritized`, `lowest-price`
*  `on_demand_base_capacity`: Minimum number of on-demand/reserved nodes.
*  `on_demand_percentage_above_base_capacity`: Once that minimum has been granted, percentage of on-demand for the rest of the total capacity.
*  `spot_allocation_strategy`: `lowest-price`, 
 `capacity-optimized` (focus on capacity),
 `capacity-optimized-prioritized` (pools with capacity, honoring instance priority), 
 `price-capacity-optimized` (recommended, pools with capacity choosing lowest price instance types).

This may be a good moment for counting instances:

```bash
aws ec2 describe-instances \
  --filter 'Name=tag:Name,Values=asgdemo' \
  --query 'Reservations[*].Instances[*].{Spot:InstanceLifecycle,Subnet:SubnetId,Type:InstanceType}' \
  --output text \
| cut -f1 \
| sort \
| uniq -c
```

:::

[]()

### Kubernetes, you said?

Nodegroups can take advantage of spot instance allocation. In fact,
the ephemeral nature of Kubenetes workloads makes a strong case
for aggressive [spot usage](https://aws.amazon.com/blogs/compute/cost-optimization-and-resilience-eks-with-spot-instances/).

```yaml
kind: ClusterConfig
...
nodeGroups:
    - minSize: 0
      maxSize: 50
      desiredCapacity: 1
      instancesDistribution:
        instanceTypes: ["m5.xlarge", "m5n.xlarge", "m5d.xlarge"] 
        onDemandBaseCapacity: 0
        onDemandPercentageAboveBaseCapacity: 0
        spotAllocationStrategy: capacity-optimized
```

[]()

### Proactive capacity rebalancing

If enabled, the ASG will monitor the risk of spot instance interruption and
replace the affected machines *before* the event occurs.

It will not work if [scale-in protection](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-instance-protection.html) is active.

```terraform
resource "aws_autoscaling_group" "nginx" {
  ...
  capacity_rebalance  = true
  ...
}
```

[]()

### LT License management

[License management](https://mng.workshop.aws/licensemanager.html) can
be integrated, automatically generating an audit of the actual usage of
the software and even limiting the creation of new instances.

```terraform
  ...
  license_specification {
    license_configuration_arn = "arn:aws:license-manager:eu-wes...lic-012def"
  }
  ...
```

::: Notes

This is a very important feature in such a dynamic environment. For example,
it can be managed for [optimizing Fortigate deployments](https://docs.fortinet.com/document/fortigate-public-cloud/7.4.0/aws-administration-guide/397979/deploying-auto-scaling-on-aws).

:::

[]()

## Lifecycle hooks

[]()

### Types of hooks

ASGs may trigger actions before completing each stage on their instances
by putting a message in EventBridge, a SNS topic or a SQS queue.

`autoscaling:EC2_INSTANCE_LAUNCHING` can be used for ensuring software
deployment before registering the new instance in a load balancer.

`autoscaling:EC2_INSTANCE_TERMINATING` is useful for cleaning up, log aggregation,
canceling an unexpected instance termination, etc.

```terraform
resource "aws_autoscaling_lifecycle_hook" "nginx" {
  name                   = "nginx_instance_launched"
  autoscaling_group_name = aws_autoscaling_group.nginx.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"

  notification_metadata = jsonencode({
    my_action = "COMPLETE_CONFIGURATION"
  })

  notification_target_arn = "arn:aws:sqs:eu-west-1:444455556666:mysqs"
  role_arn                = "arn:aws:iam::123456789012:role/sqsaccess"
}
```

### Completing the event processing

It is easy to signal the completion of a lifecycle event using the
SDK, but it is also possible to do it with the CLI (maybe from
the user data of the instance):

```bash
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
aws autoscaling complete-lifecycle-action \
  --lifecycle-hook-name nginx_instance_launched \
  --auto-scaling-group-name nginx \
  --lifecycle-action-result CONTINUE \
  --instance-id $INSTANCE_ID
```

[]()

## Speed up instance bootstrapping

[]()

### Slow boot factors

* AMI size
* Software installation
* Extensive IO operations

[]()

### In one word: Windows!

[]()

### Optimization techniques are not enough

* Install updates.
* Debloat the installation.
* Deactivate unnecessary services.
* Install required software.
* Create a custom AMI.

Creating a custom AMI is almost mandatory with Windows,
but boot EBS volume content is going to be streamed in
as-needed bases from S3, providing slow performance
even with if following best-practices.

[]()

### Warm pools

A warm pool is a group of pre-initialized (stopped, usually) EC2 instances 
aiding an Auto Scaling group to quickly scale out.

```terraform
resource "aws_autoscaling_group" "nginx" {
  ...
  warm_pool {
    pool_state                  = "Hibernated"
    min_size                    = 5
    max_group_prepared_capacity = 10
    instance_reuse_policy {
      reuse_on_scale_in = true
    }
  }
}
```

::: Notes

The ASG will keep between `min_size` and `max_group_prepared_capacity` warmed
instances. For example, with a `desired` of 2 and `min_size` of 4 the
ASG will create four instances and stop/hibernate two of them.

`pool_state` can be `stopped`, `running` or `hibernated` indicating the
desired state of the warmed instances.

`reuse_on_scale_in` should be `true` if instance are planned to be kept
in the warm pool after a scale-in event.

:::