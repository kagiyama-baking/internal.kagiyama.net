resource "aws_iam_user" "langfuse_s3" {
  name = "langfuse-user"
}

resource "aws_iam_user_policy" "langfuse_s3" {
  name = "${var.iam_prefix_user}S3LangfusePolicy"
  user = aws_iam_user.langfuse_s3.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = flatten([
          for bucket in aws_s3_bucket.langfuse : [
            bucket.arn,
            "${bucket.arn}/*",
          ]
        ])
      },
    ]
  })
}

resource "aws_iam_access_key" "langfuse_s3" {
  user = aws_iam_user.langfuse_s3.name
}
