output "s3_access_key_id" {
  description = "IAM アクセスキー ID（Ansible vault に格納すること）"
  value       = aws_iam_access_key.langfuse_s3.id
}

output "s3_secret_access_key" {
  description = "IAM シークレットアクセスキー（Ansible vault に格納すること）"
  value       = aws_iam_access_key.langfuse_s3.secret
  sensitive   = true
}

output "s3_bucket_names" {
  description = "作成された S3 バケット名"
  value = {
    event  = aws_s3_bucket.langfuse["event"].bucket
    media  = aws_s3_bucket.langfuse["media"].bucket
    export = aws_s3_bucket.langfuse["export"].bucket
  }
}
