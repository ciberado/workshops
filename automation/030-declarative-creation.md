# Declarative automation

In this tutorial, we are working with Terraform, a popular Infrastructure as Code (IAC) tool used for provisioning and managing cloud resources. 

## Environment configuration

```bash
export AWS_DEFAULT_REGION=us-east-1
```

```bash
export MYPREFIX=<your very unique prefix>
```

## Terraform installation

Before we can start using Terraform, we need to install it on our system. The first piece of code is used to install Terraform on an Amazon Linux system. It first installs yum-utils, a collection of utilities and plugins extending and supplementing yum functionality. Then, it adds the HashiCorp's official repository to the system's repository list. HashiCorp is the company that develops Terraform. Finally, it installs Terraform using the yum package manager. The last command, terraform version, is used to verify the successful installation of Terraform by displaying its version.

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

terraform version
```


## Workspaces

The next set of commands introduces the concept of Terraform workspaces. Workspaces in Terraform allow you to manage multiple environments, such as development, staging, and production, within the same infrastructure configuration. The terraform workspace list command is used to list all the workspaces.

```bash
terraform workspace list
```

Creating and managing different workspaces is straightforward in Terraform. The terraform workspace new dev command creates a new workspace named 'dev'. The terraform workspace select default and terraform workspace select dev commands are used to switch between the 'default' and 'dev' workspaces, respectively.

```bash
terraform workspace new dev
terraform workspace list
```

To change from one to another, use the `select` subcommand:

```bash
terraform workspace select default
terraform workspace list
```

```bash
terraform workspace select dev
terraform workspace list
```

## Infrastructure project creation

Here, we're creating a new directory named 'pokemon-declarative' in the home directory, and then navigating into it. This directory will hold all our Terraform configuration files for a hypothetical project, perhaps one where we're creating a cloud-based environment for a Pokemon-themed application.

```bash
cd
mkdir pokemon-declarative
cd pokemon-declarative
```

## Providers

We will define the provider and its version in a file named providers.tf. The provider block configures the named provider, in our case AWS, which is responsible for creating and managing resources. We also set the region where AWS will deploy the resources and add some default tags to help us identify and manage them.

```bash
cat << EOF > providers.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.75"
    }
  }
}

provider "aws" {
  region = var.region


  default_tags {
    tags = {
      Project = "Workstation"
      Environment : terraform.workspace
    }
  }
}
EOF

cat providers.tf
```

Once we have our provider set up, we can initialize our Terraform project. The following command will download the AWS provider plugin so that Terraform can interact with AWS.

```bash
terraform i«nit»
```

## Input variables and configuration flexibility

Next, we want to make our Terraform scripts more flexible and reusable. We will do this by defining input variables in a file named variables.tf. These variables can be used to customize the behavior of our Terraform scripts. For example, we can specify the AWS region, a unique prefix for resource names, and the port number of an application.

```hcl
cat << 'EOF' > variables.tf
variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  type        = string
  description = "Unique prefix used for configuring resource names."
}

variable "port" {
  type        = number
  description = "Port number of the application."
}
EOF

cat variables.tf
```

To provide values for these variables, we will create a file named terraform-dev.tfvars. This file will contain the actual values for our variables. Pay special attention to the port number.

```ini
cat << EOF > terraform-dev.tfvars
region = "us-east-1"
prefix = "${MYPREFIX}dev"
port   = 8080
EOF

cat terraform-dev.tfvars
```

## Locals

`locals` are another way of facilitating code readability: they are the equivalent to *constants* in other languages.

```hcl
cat << 'EOF' >> main.tf

locals {
  ubuntu = "099720109477"
}

EOF
```

```bash
cat main.tf
```

## Data

A Terraform data block is a configuration construct that allows you to fetch and compute data from various sources, which can then be used in your Terraform code. It does not create or manage resources, but instead, it retrieves data from a provider's API, a local file, or even data computed inline.

In our first step, we want to interact with our AWS environment to gather information about the default Virtual Private Cloud (VPC) and its associated subnets. We'll use the data source block in Terraform to fetch this data. The code snippet below helps us to extract the information about the default VPC and its subnets in our AWS account.

```hcl
cat << 'EOF' >> main.tf
«data» "aws_vpc" "default" {
  default = true
}

«data» "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
EOF
```

### Outputs

An output is a way to extract information about the resources you've created. Outputs are like return values for a Terraform module. They are defined within your Terraform configuration and are usually computed from resource attributes or data block attributes. Once you've defined an output, you can access its value using the terraform output command. This can be particularly useful when you want to display certain information after Terraform has completed running, or when you want to use the outputs of one module in another module, effectively creating dependencies between them.

Once we have fetched the necessary data, we want to output the VPC ID and the ID of the first subnet. This information can be useful for other parts of our infrastructure setup or for debugging purposes. 

```hcl
cat << 'EOF' > outputs.tf
output "vpc_id" {
  value = data.aws_v«pc».default.id
}

output "subnet_id" {
  value = data.aws_s«ubnets».default.ids[0]
}
EOF
```

## Planning

So now that we have gathered our data and defined our desired outputs, we need to verify that our configuration is correct. We can do this by running a 'terraform plan' command. This command compares the requested resources to the state information saved by Terraform and outputs the differences. We'll first display the contents of our main.tf and outputs.tf files to ensure they're correct, and then run the terraform plan command.

```bash
cat main.tf
cat outputs.tf
```

```bash
terraform p«lan» \
  -var-file terraform-dev.tfvars 
```


## Resources: security group

Resource block describes a physical or logical component that exists in a provider's service. This could be a compute instance, a user account, a database service, or any other entity that the provider manages. Each resource block describes one or more instances of a given resource type, identified by a type and a name. The body of the resource block defines the characteristics of the resource, such as its settings or configuration. Terraform uses these resource blocks to understand the dependencies between resources and to determine the order in which operations must be performed to create, update, or destroy resources.

In the context of a cloud-based application, it's important to ensure that the application's network security is properly configured. The security group, which acts as a virtual firewall, will control the inbound and outbound traffic for our application.

```hcl
cat << 'EOF' >> main.tf

resource "aws_security_group" "app_sg" {
  name        = "${var.prefix}_app_sg"
  description = "Application security group"
  vpc_id      = data.aws_vpc.«default».id

  ingress {
    description = "HTTP from Anywhere"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Layer : "network fabric"
  }
}
EOF
```

Once we have defined our infrastructure, it's a good practice to validate our Terraform configuration. This step checks the configuration for syntax errors, missing arguments, and other common issues. It also ensures that the configuration is set up correctly before we actually apply it.

```bash
terraform validate
```

Before we proceed to apply our configuration, we can use the terraform plan command to preview the changes that will be made. This command will output a detailed plan of what will be created, modified, or destroyed. We'll use a variable file, `terraform-dev.tfvars`, to provide values for the variables used in our configuration.

```bash
terraform plan \
  -var-file terraform-dev.tfvars 
```

Finally, we will apply our configuration using the terraform apply command. This will create the actual resources in AWS as per our configuration. Again, we'll use the `terraform-dev.tfvars` file to provide the required variable values.

```bash
terraform apply \
  -var-file terraform-dev.tfvars 
```

## Local in practice

Next we aim to dynamically fetch the most recent Ubuntu Amazon Machine Image (AMI) for our EC2 instance. We are specifically looking for the AMI for the Ubuntu Jammy 22.04 server. As you can see, we take advantage of our previously defined `local` for making the code easier to read:

```hcl
cat << 'EOF' >> main.tf

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [local.ubuntu]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
EOF
```

## Templates

we are creating a shell script template that will be used to bootstrap our EC2 instance. This script will update the package manager, install the AWS command-line interface and Java Runtime Environment, download a Java application (a Pokemon game), and start the application on a specified port. 

The most interesting part of the script is the embedded expression that will be replaced later with a `var` value, `${port}`.

```bash
cat << 'EOF' > pokemon.sh.tpl
#!/bin/sh
 
sudo apt update
sudo apt install awscli openjdk-17-jre-headless -y
wget https://github.com/ciberado/pokemon-java/releases/download/v2.0.0/pokemon-2.0.0.jar
java -jar -Dserver.port=${port} pokemon-2.0.0.jar
EOF
```

```bash
cat pokemon.sh.tpl
```

## Resources: EC2 instance

The instance is configured using all the previously declared resources. See how the user data is loaded with the `templatefile` function, allowing to change the value of the `${port}` expresssion for the one passed as input variable to the script. Also, it is worth noting that `user_data_replace_on_change` will ensure the instance is replaced with a new configuration if the user data changes.

```bash
cat << 'EOF' >> main.tf

resource "aws_instance" "app" {
  ami           = data.aws_ami.«ubuntu».id
  instance_type = "t3.micro"

  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = templatef«ile»("${path.module}/pokemon.sh.tpl", {
    port  = var.port
  })

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
    http_tokens            = "optional"
  }

  tags = {
    Name : "pokemon-server"
    Layer : "computing"
  }
}
EOF
```

Let's go and apply the new resources!

```bash
terraform apply \
  -var-file terraform-dev.tfvars 
```

## Output enhancing

It is always good to properly return useful information as the result of the execution of the script. 

```bash
cat << 'EOF' >> outputs.tf

output "instance_public_ip" {
  description = "Address of the application"
  value       = "http://${aws_instance.app.public_ip}:${var.port}"
}

EOF
```

Apply it again for getting the value:

```bash
terraform apply \
  -var-file terraform-dev.tfvars 
```