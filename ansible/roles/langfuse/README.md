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
`.env`・ClickHouse 設定 3 ファイルのいずれかに差分が出るとハンドラ「LangFuse を再起動」が走り、5 コンテナすべてが再起動される（イメージは更新されない）。ClickHouse の設定変更だけでも全体が再起動される点に注意。この再起動は依存先の起動を待たないので、ClickHouse の起動が遅いと `langfuse-web` は接続できずに終了し、自動の再起動で復帰する。`RestartCount` が増えていても healthy に戻っていれば正常。
`docker-compose.yml` の差分（イメージタグの更新など）はハンドラを発火させず、タスク側の `state: present` が変わったコンテナだけ再作成して反映する（理由は `tasks/main.yml` のコメントを参照）。イメージの取得は `pull: missing` で、同じタグが手元にあれば取得し直さない。
`.env`・ClickHouse 設定とイメージタグは同じ変更に混ぜないこと。再作成の直後にハンドラが走り、起動時の migration を中断するおそれがある。

## 運用上の注意

- **イメージは 5 つともバージョンを固定し、`pull: always` に戻さない**（`defaults/main.yml` 参照）。`latest` や `3` のような可変タグと `pull: always` を組み合わせると、別の変更のデプロイで Langfuse 本体や ClickHouse の版が意図せず上がり、DB の migration まで走る。`ansible/group_vars/` や `site.yml` を変更すると全ロールがデプロイされるので、関係のない変更でも起こり得る
- **Redis は永続化していない**。コンテナを作り直すと処理待ちのキューとキャッシュは消え、処理中のトレースがわずかに失われることがある
- **Langfuse 本体を更新する前に PostgreSQL のダンプを取る**。起動時に PostgreSQL と ClickHouse の migration が走り、**タグを戻すだけでは切り戻せない**（[本体の切り戻し](#本体の切り戻し)を参照）
- **`background_migrations` の未完了の行は、`envGate` 付きなら正常**。次のメジャー版に向けた履歴の移行で、`envGate` が示す環境変数を有効にするまで実行されない。`psql` で `select name, args->>'envGate', failed_at from background_migrations where finished_at is null;` を実行し、すべての行に `envGate` があり `failed_at` が空であることを確かめる
- **シングルノード構成には `CLICKHOUSE_CLUSTER_ENABLED=false` が必須**。デフォルトは true で、その場合 LangFuse のマイグレーションが ZooKeeper / ClickHouse Keeper を要求して起動に失敗する。`.env` から外さないこと
- **`HOSTNAME=0.0.0.0` が必要**。既定のままではコンテナ内でループバックにしか bind されず、Traefik や healthcheck から到達できない
- **S3 バケット 3 つ（event / media / export）は `tofu/` で管理**する。バケットと IAM ユーザーを作り直した場合は `cd tofu && make secret` でアクセスキーを取得し、vault の `langfuse_vault_s3_*` を更新してから本ロールを再デプロイする。詳細は [tofu/README.md](../../../tofu/README.md) を参照
- **PostgreSQL と ClickHouse はバックアップ対象外**。LLM のトレースは消失しても許容するという判断であり、backup ロールの location にも含めていない。トレース以外の設定（プロジェクト・API キー・アプリが使うプロンプト等）も同じ DB にあるため、消失時は再作成が必要になる点を承知しておくこと
- **ClickHouse のメモリチューニングは OOM 対策の結果**。`templates/clickhouse/` 配下の設定は、既定値のままでは割り当てメモリを超えて OOM Kill されたため導入した。`langfuse_clickhouse_mem_limit` を下げる場合は `max_server_memory_usage` も併せて見直すこと
- **システムテーブルの TTL を外さない**。`query_log` などは既定で無期限に増え続け、`/opt/langfuse/clickhouse` のディスクを食い潰す
- **TTL を足しても既存のデータは消えない**。定義が変わると、ClickHouse は起動時に既存のテーブルを `<テーブル>_N` に改名して作り直す。もともと TTL がなかったテーブルは改名後も期限なしで残るので、中身が不要なら `/opt/langfuse` で次のように消す

    ```bash
    docker compose exec -T langfuse-clickhouse sh -c 'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "DROP TABLE system.<テーブル>_N SYNC"'
    ```

### 本体の切り戻し

旧版は、自分の知らない ClickHouse の migration が適用済みだと起動を拒否する（`no migration found for version N`）。そのため、タグを戻す前にデータを戻す。

更新の前に、サーバの `/opt/langfuse` で次を実行して控えを取る。このダンプが PostgreSQL の唯一の控えになるので、サーバの外に持ち出さず、完了マーカーに加えて `prompts` など主要テーブルの行数も照合する。

```bash
# ClickHouse の現在の migration を控える（出力の version が切り戻しの <V>）
docker compose exec -T langfuse-clickhouse sh -c 'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "select version, dirty from schema_migrations order by sequence desc limit 1"'

# ダンプを取る（権限 0600、既存のファイルは上書きしない）
(umask 077; set -o noclobber; docker compose exec -T langfuse-database pg_dump -U langfuse langfuse > ~/langfuse-pre-vX-YYYYMMDD.sql)
tail -n 5 ~/langfuse-pre-vX-YYYYMMDD.sql | grep 'PostgreSQL database dump complete'
```

切り戻しは同じ場所で次の順に実行する。各段階の成否を確かめてから次へ進む。

```bash
# 1. Web と Worker を止める
docker compose stop langfuse-web langfuse-worker

# 2. ClickHouse の migration を、更新後の Web イメージで更新前の版まで戻す
docker compose run --rm --no-deps -T --entrypoint sh langfuse-web -c \
  'cd packages/shared && migrate -source file://clickhouse/migrations/unclustered -database "${CLICKHOUSE_MIGRATION_URL}?username=${CLICKHOUSE_USER}&password=${CLICKHOUSE_PASSWORD}&database=${CLICKHOUSE_DB:-default}&x-multi-statement=true&x-migrations-table-engine=MergeTree" goto <V>'

# 3. ダンプの完了マーカーを確かめてから、PostgreSQL を作り直して流し込む
tail -n 5 ~/langfuse-pre-vX-YYYYMMDD.sql | grep 'PostgreSQL database dump complete'
docker compose exec -T langfuse-database psql -U langfuse -d postgres -v ON_ERROR_STOP=1 -c 'DROP DATABASE langfuse' -c 'CREATE DATABASE langfuse'
docker compose exec -T langfuse-database psql -U langfuse -d langfuse -v ON_ERROR_STOP=1 -q < ~/langfuse-pre-vX-YYYYMMDD.sql
```

最後に、更新で変えたタグだけを元の版に戻す PR をマージする（可変タグには戻さない）。CD が旧版のイメージでコンテナを作り直す。

- **タグを戻す PR を先にマージしない**。旧版の Web が再起動を繰り返し、旧版の Worker が migration 後の DB で動いてしまう。手順 2 の `docker compose run` も更新後のイメージを使えなくなる
- ダンプより後の PostgreSQL の変更（更新後に編集したプロンプトなど）は失われる。ClickHouse のトレースは残るが、down migration の内容と ClickHouse の版の差で結果が変わるので、更新のたびに手元で確かめる

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
