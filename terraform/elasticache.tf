# -----------------------------------------------------------------------------
# ElastiCache Serverless (Valkey) — replaces in-cluster redis-cart
# -----------------------------------------------------------------------------

resource "aws_security_group" "elasticache" {
  name        = "${local.cluster_name}-elasticache-sg"
  description = "Allow Redis access from EKS cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.cluster_name}-elasticache-sg"
  }
}

resource "aws_elasticache_serverless_cache" "main" {
  engine = "valkey"
  name   = "${local.cluster_name}-cart"

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.elasticache.id]

  tags = {
    Name = "${local.cluster_name}-cart"
  }
}
