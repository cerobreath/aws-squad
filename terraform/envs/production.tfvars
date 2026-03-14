aws_region = "eu-central-1"

vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.0.0/22", "10.1.4.0/22"]
private_subnet_cidrs = ["10.1.64.0/19", "10.1.96.0/19"]
availability_zones   = ["eu-central-1a", "eu-central-1b"]
single_nat_gateway   = false

cluster_version                      = "1.32"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
node_instance_types                  = ["t3.large"]
node_desired_size                    = 3
node_min_size                        = 2
node_max_size                        = 5
node_disk_size                       = 50
node_capacity_type                   = "ON_DEMAND"

domain_name = "shop.whiteforge.ai"
