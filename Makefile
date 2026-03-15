# ==============================================================================
# Makefile（開発機・サーバ共用）
# ==============================================================================
# 開発機から実行（SSH経由）:
#   make deploy-test                    # テストのみ実行
#   make deploy-setup                   # セットアップを実行
#   make deploy-coredns                 # CoreDNS をデプロイ（Vault必要）
#   make deploy-portainer               # Portainer をデプロイ
#   make deploy-traefik                 # Traefik をデプロイ（Vault必要）
#   make deploy-immich                  # Immich をデプロイ（Vault必要）
#   make deploy-observability           # Observability をデプロイ（Vault必要）
#   make deploy-app                     # アプリケーション をデプロイ（Vault必要）
#   make deploy-check                   # ドライラン
#   make deploy-test SSH_HOST=my-server # ホスト名を指定して実行
#
# サーバ上で直接実行:
#   make test                           # テストのみ実行
#   make setup                          # セットアップを実行
#   make coredns                        # CoreDNS をデプロイ（Vault必要）
#   make portainer                      # Portainer をデプロイ
#   make traefik                        # Traefik をデプロイ（Vault必要）
#   make immich                         # Immich をデプロイ（Vault必要）
#   make observability                  # Observability をデプロイ（Vault必要）
#   make app                            # アプリケーション をデプロイ（Vault必要）
#   make check                          # ドライラン
# ==============================================================================

SSH_HOST  ?= internal.kagiyama.net
REMOTE_DIR ?= ~/internal.kagiyama.net
ANSIBLE_DIR = ansible

.PHONY: test setup coredns portainer traefik immich observability app check deploy-test deploy-setup deploy-coredns deploy-portainer deploy-traefik deploy-immich deploy-observability deploy-app deploy-check

# ============================================================
# サーバ上で直接実行（Ansible）
# ============================================================

# テスト用プレイブックを実行する（動作確認用）
test:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags test

# セットアップを実行する（Docker等のインストール、sudoパスワードが必要）
setup:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags setup --ask-become-pass

# CoreDNS をデプロイする（Vaultパスワードが必要）
coredns:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags coredns --ask-vault-pass

# Portainer をデプロイする
portainer:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags portainer

# Traefik をデプロイする（Vaultパスワードが必要）
traefik:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags traefik --ask-vault-pass

# Immich をデプロイする（Vaultパスワードが必要）
immich:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags immich --ask-vault-pass

# Observability をデプロイする（Vaultパスワードが必要）
observability:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags observability --ask-vault-pass

# アプリケーション をデプロイする（Vaultパスワードが必要）
app:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags app --ask-vault-pass

# ドライラン（実際には変更を適用せず、実行内容を確認する）
check:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --check --ask-become-pass

# ============================================================
# 開発機から実行（SSH → git pull → Ansible）
# ============================================================
# -A: エージェントフォワーディングでgit pullの認証を委譲
# リモートは main ブランチで git pull するため、
# PR マージ後に実行すること

# リモートで pull + テストのみ実行
deploy-test:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make test'"

# リモートで pull + セットアップ実行（sudoパスワードが必要）
deploy-setup:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make setup'"

# リモートで pull + CoreDNS デプロイ（Vaultパスワードが必要）
deploy-coredns:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make coredns'"

# リモートで pull + Portainer デプロイ
deploy-portainer:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make portainer'"

# リモートで pull + Traefik デプロイ（Vaultパスワードが必要）
deploy-traefik:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make traefik'"

# リモートで pull + Immich デプロイ（Vaultパスワードが必要）
deploy-immich:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make immich'"

# リモートで pull + Observability デプロイ（Vaultパスワードが必要）
deploy-observability:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make observability'"

# リモートで pull + アプリケーション デプロイ（Vaultパスワードが必要）
deploy-app:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make app'"

# リモートで pull + ドライラン
deploy-check:
	ssh -At $(SSH_HOST) "bash -l -c 'cd $(REMOTE_DIR) && git pull && make check'"
