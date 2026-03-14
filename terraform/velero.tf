# -----------------------------------------------------------------------------
# Velero — S3 bucket for backups + IAM role with IRSA
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "velero" {
  bucket        = "${var.project_name}-${terraform.workspace}-velero-backups"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${terraform.workspace}-velero-backups"
  }
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# IAM role for Velero using IRSA
resource "aws_iam_role" "velero" {
  name = "${local.cluster_name}-velero-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:velero:velero-server"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "velero" {
  name = "${local.cluster_name}-velero-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = "${aws_s3_bucket.velero.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.velero.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "velero" {
  policy_arn = aws_iam_policy.velero.arn
  role       = aws_iam_role.velero.name
}
