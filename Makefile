# ==============================================================================
# 開発機からのデプロイ用 Makefile
# ==============================================================================
# SSH接続先の設定（環境に合わせて変更してください）
#   - SSH_HOST: ~/.ssh/config で設定したホスト名
#   - REMOTE_DIR: サーバ上のリポジトリパス
#
# 使い方:
#   make deploy-test                    # テストのみ実行
#   make deploy-setup                   # セットアップを実行
#   make deploy                         # テスト＋セットアップを実行
#   make deploy SSH_HOST=my-server      # ホスト名を指定して実行
# ==============================================================================

SSH_HOST ?= ubuntu-server
REMOTE_DIR ?= ~/internal.kagiyama.net

.PHONY: deploy deploy-test deploy-setup deploy-check push

# git push してからリモートで pull + 全タスク実行
deploy: push
	ssh -t $(SSH_HOST) "cd $(REMOTE_DIR) && git pull && cd ansible && make all"

# git push してからリモートで pull + テストのみ実行
deploy-test: push
	ssh -t $(SSH_HOST) "cd $(REMOTE_DIR) && git pull && cd ansible && make test"

# git push してからリモートで pull + セットアップ実行（sudoパスワード入力あり）
deploy-setup: push
	ssh -t $(SSH_HOST) "cd $(REMOTE_DIR) && git pull && cd ansible && make setup"

# git push してからリモートで pull + ドライラン
deploy-check: push
	ssh -t $(SSH_HOST) "cd $(REMOTE_DIR) && git pull && cd ansible && make check"

# 現在のブランチを push する（deploy の前段階）
push:
	git push
