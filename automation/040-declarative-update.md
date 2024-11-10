# Declarative management


## Port replacement

The objective here is to modify a specific parameter, in this case, the port number, of our Terraform configuration in a development environment. We will be using Terraform variable files (tfvars) to achieve this. We will first update the `tfvars` file for our dev environment with the new desired port number. Then, we will use this tfvars file with the Terraform plan and apply commands to see and implement the changes respectively.

```ini
cat << EOF > terraform-dev.tfvars
region = "us-east-1"
prefix = "${MYPREFIX}dev"
port   = 80
EOF

cat terraform-dev.tfvars
```

```bash
terraform plan \
  -var-file terraform-dev.tfvars 
```

```bash
terraform apply \
  -var-file terraform-dev.tfvars 
```

And that's all! I hope you find value in how straightforward managing configuration changes can be with a declarative approach, such as the one presented with Terraform.


## Clean up

Declarative management is also extremely useful for removing unwanted resources, a key task in dynamic environments such as those deployed in the cloud.

```bash
terraform apply \
  -destroy \
  -var-file terraform-dev.tfvars  
```
