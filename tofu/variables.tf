variable "aws_region" {
  description = "AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "iam_prefix_user" {
  description = "IAMユーザー用のIAMポリシーとロールのプレフィックス"
  type        = string
  default     = "UserKagiyamaBaking"
}

variable "project_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "kagiyama-baking"
}
