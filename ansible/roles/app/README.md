# app ロール

アプリケーション本体（kawashiro-server: Django REST API + React SPA）をデプロイするロール。

## 概要

Django API・Celery ワーカー・Celery Beat・Redis・PostgreSQL・フロントエンドの 6 コンテナを Docker Compose で起動し、Traefik 経由で HTTPS 公開する。
公開 FQDN は `app_traefik_host`（`ansible/group_vars/local.yml`）で、本サイトのルートドメインにあたる。site.yml のタグは `app`。
CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象であり、`ansible/roles/app/` の変更が main にマージされると自動デプロイされる。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `frontend` | `ghcr.io/kagiyama-baking/kawashiro-server/frontend` | 80 | React SPA の配信と API へのリバースプロキシ。Traefik のルーティング先 |
| `django-api` | `ghcr.io/kagiyama-baking/kawashiro-server/django-api` | 8000 | gunicorn で動く REST API。起動時に `migrate` と `collectstatic` を実行 |
| `celery-worker` | 同上 | — | バックグラウンドタスクの実行 |
| `celery-beat` | 同上 | — | 定期タスクのスケジューラ（`DatabaseScheduler`） |
| `redis` | `redis` | 6379 | Celery のブローカー兼結果バックエンド |
| `app-database` | `pgvector/pgvector` | 5432 | アプリケーション DB（pgvector 拡張つき） |

イメージのタグは `defaults/main.yml` を参照。
`django-api` / `celery-worker` / `celery-beat` は同一イメージを `command` だけ変えて起動する。
`frontend` のみ `traefik_network_name` と `app-internal` の両方に属し、残りは `app-internal` に閉じる。ホストポートを公開するコンテナは無く、外部からの入口は Traefik → `frontend` の 1 本のみ。

## 配置ファイル

| 配置先 | テンプレート | 権限 | 内容 |
| --- | --- | --- | --- |
| `/opt/app/.env` | `templates/env.j2` | 0600 | Django の秘密鍵・DB 接続情報・Celery・TTS・LiteLLM・Langfuse の設定 |
| `/opt/app/docker-compose.yml` | `templates/docker-compose.yml.j2` | 0600 | 6 コンテナの定義 |
| `/opt/app/frontend/nginx.conf` | `templates/nginx.conf.j2` | 0644 | `frontend` の nginx 設定（コンテナへ read-only でマウント） |

ロールが作成するディレクトリは `/opt/app/django-api`、同 `staticfiles`、同 `media`、`/opt/app/frontend` の 4 つ。
DB データ用の `app_db_data_location` は作成しない。PostgreSQL が所有権をコンテナ UID に変更するため、Ansible で作ると再デプロイ時の `chmod` が EPERM で失敗する。Compose の初回起動に任せる。

## 主要変数

| 変数 | 設計・運用上の意図 |
| --- | --- |
| `app_django_image` / `app_frontend_image` | **このリポジトリではビルドしない**。kawashiro-server リポジトリ側の CI がビルドして push したイメージを参照する |
| `app_sbv2_service_url` | 外部 TTS サービスの接続先。Tailscale 上の別ホストで動く（後述） |
| `app_django_timeout` | gunicorn のワーカータイムアウト。LLM 呼び出しや音声合成を含むリクエストが長時間化するため大きく取っている |
| `app_celery_worker_concurrency` | ワーカーの並列度。メモリ上限とあわせて調整する |
| `app_db_image` | pgvector 拡張つき PostgreSQL。ベクトル検索に必要で、素の `postgres` へは差し替えられない |
| `app_litellm_proxy_url` / `app_langfuse_base_url` | 同一ホスト上の LiteLLM / Langfuse への接続先。FQDN が直書きされている（後述） |

### Vault 変数

`vars/vault.yml`（ansible-vault で暗号化）に以下を保持する。

- `app_vault_django_secret_key`
- `app_vault_encryption_key`
- `app_vault_db_password`
- `app_vault_litellm_master_key`
- `app_vault_langfuse_secret_key`
- `app_vault_langfuse_public_key`

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make app` |
| 開発機 | `make deploy-app` |

Vault パスワードが必要（`--ask-vault-pass`）。sudo パスワードは不要。
`nginx.conf` / `.env` / `docker-compose.yml` のいずれかに差分が出るとハンドラ `App を再起動` が発火し、Compose プロジェクト全体が `state: restarted` で再起動する。
タスク・ハンドラともに `pull: always` を指定しており、**タグが変わらなくても毎回イメージを取得し直す**。アプリのイメージが可変タグで更新される運用のため、これがデプロイでアプリを最新にする仕組みそのものになっている。

## 運用上の注意

- **アプリのイメージはこのリポジトリの管轄外**。コード変更を本番へ反映する経路は「kawashiro-server 側の CI がイメージを push」→「このロールを再デプロイして pull させる」の 2 段階になる。Ansible 側だけを見てもデプロイされた中身は分からない
- **外部 TTS サービスへの依存がある**。`app_sbv2_service_url` は Tailscale 上の別ホストを指しており、このリポジトリの管理外にある。当該ホストが停止すると**音声合成機能のみが縮退**し、他の機能は動き続ける。API のタイムアウトが増えた場合はまずこの接続先の生死を確認する
- **DB は PostgreSQL（pgvector）であり SQLite ではない**。過去に SQLite から移行済みで、バックアップやリストアの手順も PostgreSQL 前提になっている。古い記述を見かけたら疑うこと
- **`celery-beat` の healthcheck は `pgrep` によるプロセス生存確認**。`celery inspect ping` は全ワーカーへの broadcast であり、ワーカーではない beat は応答せずタイムアウトする。さらに `CMD-SHELL` にすると親 `sh` のコマンドラインがパターンに自己マッチするため、`CMD` 形式（exec）で `pgrep` を直接呼ぶ必要がある。この 2 点はどちらも実際に踏んだ罠なので変更しないこと
- **`frontend` の nginx 設定には理由のある記述が 4 つある**（`templates/nginx.conf.j2`）
    - `resolver 127.0.0.11` ＋ `set $backend ...` — nginx は起動時に upstream のホスト名を解決しようとし、`depends_on` は DNS 解決可能を保証しないため、変数経由でリクエスト時解決にしている。upstream はコンテナ名で解決される
    - `rewrite ^/api/(.*) /$1 break;` — `proxy_pass` に変数を使うと自動 URI 書き換えが無効になるため、`/api/` プレフィックスの除去を明示的に行っている
    - `.mjs` の MIME 上書き — nginx 同梱の `mime.types` では `application/octet-stream` 扱いになることがあり、`X-Content-Type-Options: nosniff` と組み合わさって動的 import が失敗する
    - `client_max_body_size` — 大容量ファイルのアップロードを通すため `/api/` に限って引き上げている
- `frontend` は `cap_drop: ALL` で動かすため、`/var/cache/nginx`・`/tmp`・`/run` を tmpfs でマウントし、いずれも nginx ユーザーの uid/gid を指定している。tmpfs は既定で root 所有になるため、この指定を外すと起動しない
- **`app_litellm_proxy_url` と `app_langfuse_base_url` に FQDN が直書きされている**。他ロールの FQDN は `ansible/group_vars/local.yml`（`litellm_traefik_host` / `langfuse_traefik_host`）が単一の情報源なので、この 2 つはそこから外れている既知の課題。FQDN を変更する際は group_vars とこの defaults の両方を直す必要がある
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ（`localhost` への local 接続）。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、必ず `make deploy-app` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/troubleshooting.md](../../../docs/troubleshooting.md) — 障害調査の起点
- [litellm ロール](../litellm/README.md) — LLM ゲートウェイ
- [langfuse ロール](../langfuse/README.md) — LLMOps トレーシング
- [traefik ロール](../traefik/README.md) — HTTPS 終端と証明書
- [coredns ロール](../coredns/README.md) — 内部ドメインの名前解決
