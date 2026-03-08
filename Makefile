# ==============================================================================
# Makefile（開発機・サーバ共用）
# ==============================================================================
# 開発機から実行（SSH経由）:
#   make deploy-test                    # テストのみ実行
#   make deploy-setup                   # セットアップを実行
#   make deploy-check                   # ドライラン
#   make deploy-test SSH_HOST=my-server # ホスト名を指定して実行
#
# サーバ上で直接実行:
#   make test                           # テストのみ実行
#   make setup                          # セットアップを実行
#   make check                          # ドライラン
# ==============================================================================

SSH_HOST  ?= internal.kagiyama.net
REMOTE_DIR ?= ~/internal.kagiyama.net
ANSIBLE_DIR = ansible

.PHONY: test setup check deploy-test deploy-setup deploy-check push

# ============================================================
# サーバ上で直接実行（Ansible）
# ============================================================

# テスト用プレイブックを実行する（動作確認用）
test:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags test

# セットアップを実行する（Docker等のインストール、sudoパスワードが必要）
setup:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags setup --ask-become-pass

# ドライラン（実際には変更を適用せず、実行内容を確認する）
check:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --check --ask-become-pass

# ============================================================
# 開発機から実行（git push → SSH → git pull → Ansible）
# ============================================================
# -A: エージェントフォワーディングでgit pullの認証を委譲

# git push してからリモートで pull + テストのみ実行
deploy-test: push
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make test'"

# git push してからリモートで pull + セットアップ実行（sudoパスワードが必要）
deploy-setup: push
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make setup'"

# git push してからリモートで pull + ドライラン
deploy-check: push
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make check'"

# 現在のブランチを push する（deploy の前段階）
push:
	git push
