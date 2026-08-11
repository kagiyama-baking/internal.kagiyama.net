# Technology Stack

## Architecture

シングルホスト（Ubuntu Server 24.04 LTS on UTM）に対する **Pull/Push 兼用型 IaC**。

- Ansible はリポジトリのルートから `ansible/site.yml` を起点に、`localhost` に対して `ansible_connection=local` で実行される（開発機からは SSH 越しに `make deploy-*`、サーバ上では `make <role>` で同じプレイブックを呼び分ける）
- すべてのアプリは Docker Compose v2 サービスとして `/opt/<role>/` 配下に展開され、共有ネットワーク `traefik-public` で Traefik と接続される
- 外部公開は Traefik が一手に担い、TLS は Let's Encrypt（Route 53 DNS-01 チャレンジ）で自動取得
- 開発機 ⇄ サーバ間およびクライアント ⇄ サーバ間の通信は Tailscale サブネットルーティングで保護

## Core Technologies

- **構成管理**: Ansible（collections: `community.general`, `community.docker`, `ansible.posix`）
- **コンテナ実行**: Docker / Docker Compose v2（`community.docker.docker_compose_v2`）
- **クラウド IaC**: OpenTofu `>= 1.6`（AWS provider `~> 5.0`）
- **ネットワーク**: Tailscale（SSH・サブネットルーティング・GitHub Actions 連携）
- **言語ランタイム**: Python `>= 3.13`（lint ツール用、依存は **uv** で管理）
- **CI/CD**: GitHub Actions（`ansible_lint.yml` / `deploy.yml` / `docs_check.yml`）

## Key Libraries

開発パターンに影響する主要ツールのみ列挙する。

- `ansible-lint`（profile: `production`）
- `yamllint`（line-length 120、indent 4 スペース、`truthy` は `true/false/yes/no` 許可）
- `autorestic` / `restic`（バックアップロール内で利用）

## Development Standards

### Lint & Code Style

- YAML は **4 スペースインデント**、シーケンスも同じく 4 スペース、行長 120 まで（`.yamllint.yml`）
- `ansible/roles/*/vars/vault.yml` は yamllint の対象から除外する（暗号化済みのため）
- ansible-lint は `production` プロファイルを通過すること（`.ansible-lint`）
- Markdown ファイルはデプロイ対象から除外する（CI のパス除外で `'!ansible/**/*.md'`）

### Python 依存管理（重要）

- **必ず uv を使う**。`pip install` は禁止
- 開発依存は `pyproject.toml` の `[dependency-groups].dev` に集約し、`uv sync` / `uv add <pkg>` / `uv run <cmd>` で操作する

### Secrets

- 秘密値は `ansible/roles/<role>/vars/vault.yml` に Ansible Vault で暗号化して格納
- 平文の defaults（`defaults/main.yml`）に空文字を置き、vault でオーバーライドする運用
- Vault パスワードは CI では `secrets.ANSIBLE_VAULT_PASSWORD` をファイル経由で受け渡す（引数に含めない）

### Idempotency & Notification

- ファイル配置（template/copy）の変更は handlers で `notify: <Role> を再起動` を発火させ、コンテナを再起動する
- 直接 `docker_compose_v2` を呼ぶタスクは `state: present` を基本形にする。`pull` は可変タグ運用のロール（app / litellm / langfuse）で `always`、バージョン固定タグのロールでは `missing` を使う

## Development Environment

### Required Tools

- Python 3.13 + uv
- Ansible（サーバ側は `pipx install ansible --include-deps`）
- Docker / Docker Compose v2
- Make / Git / SSH
- Tailscale（リモートデプロイ時）
- OpenTofu `>= 1.6`（LangFuse 用 S3 / IAM を作成・更新する時のみ）

### Common Commands

```bash
# Lint（開発機）
uv sync
uv run yamllint ansible/
uv run ansible-lint -c .ansible-lint ansible/

# ドキュメント整合性チェック（開発機、PR 前に必ず実行）
uv run python scripts/check_docs.py

# ロール単位のデプロイ（開発機 → サーバ、SSH 経由）
make deploy-test                       # 動作確認用ロール
make deploy-setup                      # OS セットアップ（sudo パス要）
make deploy-<role>                     # 各サービスのデプロイ（Vault パス要）
make deploy-check                      # 全体ドライラン

# サーバ上で直接実行
make <role>                            # 例: make traefik, make immich

# OpenTofu（LangFuse 用 S3/IAM）
cd tofu && make plan && make apply
```

## Key Technical Decisions

- **ロール = サービス = タグ**: `site.yml` 内で 1 ロール = 1 プレイ = 1 タグ。CI/CD と Makefile の双方が「タグ名」を共通の選択キーとして扱い、変更されたロールだけを再適用する設計
- **Traefik 単一受け口 + Let's Encrypt DNS-01**: 内部ドメイン `*.internal.kagiyama.net` を Route 53 で管理し、Traefik が DNS-01 で証明書を自動取得（内部公開でも HTTPS）
- **CoreDNS で内部 DNS を提供**: ホストの systemd-resolved スタブリスナーを無効化し、ポート 53 を CoreDNS に明け渡す
- **Docker daemon の DNS 上流を CoreDNS に固定**: `/etc/docker/daemon.json` の `dns` はホスト自身（= CoreDNS）を指す。8.8.8.8 等の外部 DNS の直指定は内部ドメイン解決を壊すため禁止（2026-08 の DNS 障害 PR #112/#113/#115 の再発防止。詳細は `docs/dns.md`）
- **Vault 不要ロールの分岐**: Vault 不要は test / setup / portainer の 3 つ。うち CD 対象は portainer のみで、CI スクリプトと Makefile の両方に portainer だけ Vault パスワードを渡さない分岐が明示的に存在する

---
_Document standards and patterns, not every dependency_
