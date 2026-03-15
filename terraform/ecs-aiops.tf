# -----------------------------------------------------------------------------
# AIOps — ECS Fargate deployment
# -----------------------------------------------------------------------------

# ECS Cluster
resource "aws_ecs_cluster" "aiops" {
  name = "${local.cluster_name}-aiops"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "aiops" {
  name              = "/ecs/${local.cluster_name}-aiops"
  retention_in_days = 7
}

# -----------------------------------------------------------------------------
# IAM — Task Execution Role (ECR pull, logs, SSM secrets)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "aiops_execution" {
  name = "${local.cluster_name}-aiops-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "aiops_execution_base" {
  role       = aws_iam_role.aiops_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "aiops_execution_ssm" {
  name = "ssm-read"
  role = aws_iam_role.aiops_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameters",
        "ssm:GetParameter",
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${local.cluster_name}/aiops/*"
    }]
  })
}

# -----------------------------------------------------------------------------
# IAM — Task Role (Bedrock, EKS)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "aiops_task" {
  name = "${local.cluster_name}-aiops-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "aiops_task_bedrock" {
  name = "bedrock"
  role = aws_iam_role.aiops_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "aiops_task_eks" {
  name = "eks"
  role = aws_iam_role.aiops_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = aws_eks_cluster.main.arn
    }]
  })
}

# EKS Access Entry — allows the task role to use kubectl
resource "aws_eks_access_entry" "aiops" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.aiops_task.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "aiops" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.aiops_task.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.aiops]
}

# Allow ECS tasks to reach the EKS API server (port 443) via private endpoint
resource "aws_security_group_rule" "aiops_to_eks" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aiops_task.id
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# -----------------------------------------------------------------------------
# SSM Parameter for Grafana token (placeholder, updated by CI/CD)
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "aiops_grafana_token" {
  name  = "/${local.cluster_name}/aiops/grafana-token"
  type  = "SecureString"
  value = var.grafana_sa_token

  lifecycle {
    ignore_changes = [value]
  }
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "aiops_alb" {
  name_prefix = "${local.cluster_name}-aiops-alb-"
  description = "AIOps ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "aiops_task" {
  name_prefix = "${local.cluster_name}-aiops-task-"
  description = "AIOps ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.aiops_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------

resource "aws_lb" "aiops" {
  name                       = "${local.cluster_name}-aiops"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.aiops_alb.id]
  subnets                    = aws_subnet.public[*].id
  idle_timeout               = 300
}

resource "aws_lb_target_group" "aiops" {
  name        = "${local.cluster_name}-aiops"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "aiops_https" {
  load_balancer_arn = aws_lb.aiops.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.aiops.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aiops.arn
  }
}

# -----------------------------------------------------------------------------
# ECS Task Definition + Service
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "aiops" {
  family                   = "${local.cluster_name}-aiops"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.aiops_execution.arn
  task_role_arn            = aws_iam_role.aiops_task.arn

  container_definitions = jsonencode([{
    name      = "aiops"
    image     = "${local.ecr_urls["aiops"]}:latest"
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "CLUSTER_NAME", value = aws_eks_cluster.main.name },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region },
      { name = "GRAFANA_URL", value = "https://${local.grafana_domain}" },
      { name = "GRAFANA_AM_DATASOURCE_UID", value = "alertmanager" },
      { name = "AIOPS_DAEMON_ENABLED", value = "true" },
      { name = "LOG_LEVEL", value = "INFO" },
    ]

    secrets = [{
      name      = "GRAFANA_SERVICE_ACCOUNT_TOKEN"
      valueFrom = aws_ssm_parameter.aiops_grafana_token.arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.aiops.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "aiops"
      }
    }
  }])
}

resource "aws_ecs_service" "aiops" {
  name            = "aiops"
  cluster         = aws_ecs_cluster.aiops.id
  task_definition = aws_ecs_task_definition.aiops.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.aiops_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.aiops.arn
    container_name   = "aiops"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.aiops_https]
}
