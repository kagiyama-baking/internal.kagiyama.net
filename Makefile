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

deploy-test: push
	ssh -t $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make test'"

deploy-setup: push
	ssh -t $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make setup'"

deploy-check: push
	ssh -t $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make check'"

push:
	git push
