locals {
  buckets = {
    event  = "${var.project_prefix}-langfuse-event"
    media  = "${var.project_prefix}-langfuse-media"
    export = "${var.project_prefix}-langfuse-export"
  }
}

resource "aws_s3_bucket" "langfuse" {
  for_each = local.buckets
  bucket   = each.value
}

resource "aws_s3_bucket_public_access_block" "langfuse" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.langfuse[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "langfuse" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.langfuse[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
