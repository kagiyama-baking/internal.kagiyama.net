# ==============================================================================
# OpenTofu Makefile
# ==============================================================================
# 使い方:
#   make init      # プロバイダーのインストール
#   make plan      # 実行計画を確認
#   make apply     # リソースを作成・更新
#   make destroy   # リソースを削除
#   make output    # 出力値を表示
#   make secret    # シークレットアクセスキーを表示（Ansible vault 格納用）
# ==============================================================================

.PHONY: init plan apply destroy output secret fmt validate

# プロバイダーのインストール
init:
	tofu init

# 実行計画を確認（ドライラン）
plan:
	tofu plan

# リソースを作成・更新
apply:
	tofu apply

# リソースを削除
destroy:
	tofu destroy

# 出力値を表示
output:
	tofu output

# シークレットアクセスキーを表示（Ansible vault 格納用）
secret:
	@echo "=== S3 Access Key ID ==="
	@tofu output -raw s3_access_key_id
	@echo ""
	@echo "=== S3 Secret Access Key ==="
	@tofu output -raw s3_secret_access_key
	@echo ""

# コードフォーマット
fmt:
	tofu fmt

# 構文チェック
validate:
	tofu validate
