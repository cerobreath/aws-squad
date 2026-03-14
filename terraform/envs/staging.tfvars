aws_region = "eu-central-1"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/22", "10.0.4.0/22"]
private_subnet_cidrs = ["10.0.64.0/19", "10.0.96.0/19"]
availability_zones   = ["eu-central-1a", "eu-central-1b"]
single_nat_gateway   = true

cluster_version                      = "1.32"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
node_instance_types                  = ["t3.medium"]
node_desired_size                    = 2
node_min_size                        = 1
node_max_size                        = 3
node_disk_size                       = 30
node_capacity_type                   = "ON_DEMAND"

domain_name = "shop.whiteforge.ai"
