# langfuse ロール

LLM のトレース・評価基盤である LangFuse v3 をデプロイするロール。

## 概要

LangFuse Web / Worker と、それが依存する PostgreSQL・ClickHouse・Redis を Docker Compose で起動し、Traefik 経由で `langfuse.internal.kagiyama.net`（`langfuse_traefik_host`）に公開する。
site.yml のタグは `langfuse`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象であり、`ansible/roles/langfuse/` の変更が main にマージされると自動デプロイされる。
イベント・メディア・エクスポートの実体は AWS S3 に保存し、S3 バケットと IAM ユーザーは `tofu/` の OpenTofu で管理する。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `langfuse-web` | `langfuse/langfuse` | 3000（`langfuse_web_port`） | Web UI と API。Traefik 配下で公開 |
| `langfuse-worker` | `langfuse/langfuse-worker` | 3000（`.env` の `PORT` を共有） | イベントの非同期処理。外部公開なし |
| `langfuse-database` | `postgres` | 5432 | メタデータ（プロジェクト・ユーザー・設定等） |
| `langfuse-clickhouse` | `clickhouse/clickhouse-server` | 8123 / 9000 | トレースの OLAP ストア |
| `langfuse-redis` | `redis` | 6379 | キューおよびキャッシュ |

イメージのタグは `defaults/main.yml` 参照。
`langfuse-web` のみ Traefik 公開用ネットワーク（`traefik_network_name`／外部ネットワーク）に接続し、他は `langfuse-internal` に閉じる。
PostgreSQL と ClickHouse は `TZ=UTC` を明示している（LangFuse は UTC 前提）。

## 配置ファイル

| 配置先 | テンプレート | パーミッション |
| --- | --- | --- |
| `/opt/langfuse/.env` | `templates/env.j2` | 0600 |
| `/opt/langfuse/docker-compose.yml` | `templates/docker-compose.yml.j2` | 0600 |
| `/opt/langfuse/clickhouse-config/config.d/memory.xml` | `templates/clickhouse/config.d/memory.xml.j2` | 0644 |
| `/opt/langfuse/clickhouse-config/config.d/logging.xml` | `templates/clickhouse/config.d/logging.xml.j2` | 0644 |
| `/opt/langfuse/clickhouse-config/users.d/memory.xml` | `templates/clickhouse/users.d/memory.xml.j2` | 0644 |
| `/opt/langfuse/postgres/`, `/opt/langfuse/clickhouse/` | （データボリューム） | — |

`.env` は Web / Worker 双方の `env_file` として共有される。ClickHouse の設定はドロップイン形式で read-only マウントする。

## 主要変数

| 変数 | 説明 |
| --- | --- |
| `langfuse_clickhouse_max_server_memory_usage` | ClickHouse サーバー全体のメモリ上限。割合ではなく絶対値で固定する（OOM 対策） |
| `langfuse_clickhouse_mark_cache_size` | インデックスマークキャッシュ。デフォルトの 5GB は低メモリ環境で過大なため削減済み |
| `langfuse_clickhouse_max_memory_usage` / `_for_user` | 1 クエリ / 1 ユーザーあたりのメモリ上限 |
| `langfuse_clickhouse_system_log_ttl_days` | `query_log` 等のシステムテーブルの TTL。無制限に肥大化するため必須 |
| `langfuse_s3_event_bucket` / `_media_bucket` / `_export_bucket` | 用途別の S3 バケット名。実体は `tofu/` で管理 |
| `langfuse_nextauth_url` | `langfuse_traefik_host` から組み立てる公開 URL。認証コールバックに使われる |
| `langfuse_*_mem_limit` / `langfuse_*_cpus` | 各コンテナのリソース上限 |

具体的な値は `defaults/main.yml` を参照。

### Vault 変数

`vars/vault.yml`（Ansible Vault 暗号化）に以下を定義する。

- `langfuse_vault_nextauth_secret` — NextAuth のセッション署名鍵
- `langfuse_vault_salt` — ハッシュ用ソルト
- `langfuse_vault_encryption_key` — API キー等の暗号化鍵
- `langfuse_vault_db_password` — PostgreSQL のパスワード
- `langfuse_vault_clickhouse_password` — ClickHouse のパスワード
- `langfuse_vault_redis_password` — Redis のパスワード
- `langfuse_vault_s3_access_key_id` — S3 アクセスキー ID
- `langfuse_vault_s3_secret_access_key` — S3 シークレットアクセスキー

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make langfuse` |
| 開発機 | `make deploy-langfuse` |

Vault パスワードが必要（Makefile のターゲットに `--ask-vault-pass` 組み込み済み）。sudo パスワードは不要。
`.env`・`docker-compose.yml`・ClickHouse 設定 3 ファイルのいずれかに差分が出るとハンドラ「LangFuse を再起動」が走り、5 コンテナすべてが `pull: always` 付きで再起動される。ClickHouse の設定変更だけでも全体が再起動される点に注意。

## 運用上の注意

- **ClickHouse だけがバージョン非固定**。`langfuse_clickhouse_image` は `:latest` を指しており、他ロール・他コンテナがすべてバージョン固定であるのに対しここだけ例外になっている。`pull: always` で再起動するたびに上流の最新版へ入れ替わり得るため、再起動後に ClickHouse が起動しない場合はまずイメージの更新を疑う。既知のリスクとして記録する
- **シングルノード構成には `CLICKHOUSE_CLUSTER_ENABLED=false` が必須**。デフォルトは true で、その場合 LangFuse のマイグレーションが ZooKeeper / ClickHouse Keeper を要求して起動に失敗する。`.env` から外さないこと
- **`HOSTNAME=0.0.0.0` が必要**。既定のままではコンテナ内でループバックにしか bind されず、Traefik や healthcheck から到達できない
- **S3 バケット 3 つ（event / media / export）は `tofu/` で管理**する。バケットと IAM ユーザーを作り直した場合は `cd tofu && make secret` でアクセスキーを取得し、vault の `langfuse_vault_s3_*` を更新してから本ロールを再デプロイする。詳細は [tofu/README.md](../../../tofu/README.md) を参照
- **PostgreSQL と ClickHouse はバックアップ対象外**。LLM のトレースは消失しても許容するという判断であり、backup ロールの location にも含めていない。トレース以外の設定（プロジェクト・API キー等）も同じ DB にあるため、消失時は再作成が必要になる点を承知しておくこと
- **ClickHouse のメモリチューニングは OOM 対策の結果**。`templates/clickhouse/` 配下の設定は、既定値のままでは割り当てメモリを超えて OOM Kill されたため導入した。`langfuse_clickhouse_mem_limit` を下げる場合は `max_server_memory_usage` も併せて見直すこと
- **システムテーブルの TTL を外さない**。`query_log` などは既定で無期限に増え続け、`/opt/langfuse/clickhouse` のディスクを食い潰す

## AWS IAM ポリシー（LangFuse S3 用）

langfuse ロールで使用する IAM ユーザーには、LangFuse 用 S3 バケット 3 つ（event, media, export）への読み書きのみ許可する最小権限ポリシーを推奨する。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::LANGFUSE_EVENT_BUCKET",
                "arn:aws:s3:::LANGFUSE_EVENT_BUCKET/*",
                "arn:aws:s3:::LANGFUSE_MEDIA_BUCKET",
                "arn:aws:s3:::LANGFUSE_MEDIA_BUCKET/*",
                "arn:aws:s3:::LANGFUSE_EXPORT_BUCKET",
                "arn:aws:s3:::LANGFUSE_EXPORT_BUCKET/*"
            ]
        }
    ]
}
```

> **Note:** バケット名は実際の値に置き換えること。このポリシーは `tofu/` の OpenTofu で自動プロビジョニングされるため、手動作成は通常不要。

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [tofu/README.md](../../../tofu/README.md) — S3 バケット・IAM ユーザーの管理
- [litellm ロール](../litellm/README.md) — トレースの送信元
- [traefik ロール](../traefik/README.md) — リバースプロキシと TLS 終端
