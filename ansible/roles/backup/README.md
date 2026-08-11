# backup ロール

restic / autorestic によるサーバデータの日次バックアップ（→ AWS S3）を構成するロール。

## 概要

ホスト上に restic と autorestic のバイナリを配置し、PostgreSQL のダンプ取得からバックアップ・古い世代の削除までを行うスクリプトと cron ジョブを登録する。
コンテナは持たず、FQDN も公開しない。site.yml のタグは `backup`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象であり、`ansible/roles/backup/` の変更が main にマージされると自動デプロイされる。
バックアップの保存先は AWS S3 で、restic により暗号化された状態で格納される。

## 構成要素

| 種別 | 配置先 | 説明 |
| --- | --- | --- |
| バイナリ | `/opt/backup/bin/restic` | GitHub Releases から取得。SHA256SUMS で検証 |
| バイナリ | `/opt/backup/bin/autorestic` | 同上。restic のラッパー |
| 設定 | `/opt/backup/.autorestic.yml`（0600） | `templates/autorestic.yml.j2`。バックエンドと location の定義 |
| スクリプト | `/opt/backup/backup.sh`（0700） | `templates/backup.sh.j2`。ダンプ → backup → forget を実行 |
| ダンプ置き場 | `/opt/backup/dumps/immich`, `/opt/backup/dumps/app` | `pg_dump` の出力先。実行のたびに削除される |
| cron | `autorestic-backup` | `/opt/backup/backup.sh` を毎日実行（時刻は `defaults/main.yml` 参照） |

バイナリはアーキテクチャ（`aarch64` なら arm64、それ以外は amd64）を判定して取得し、既にインストール済みで同じバージョンならダウンロードをスキップする。
`/opt/backup`（`backup_base_dir`）の作成と `sqlite3` / `bzip2` のインストールは setup ロールで完了済みであることが前提。
ロール実行の最後に `autorestic check` を走らせ、S3 上の restic リポジトリが未初期化であれば初期化する。

## バックアップ対象

| Location | 対象 | 方法 |
| --- | --- | --- |
| `immich-db` | Immich の PostgreSQL | `pg_dump` でダンプしてからバックアップ |
| `immich-library` | Immich の写真・動画（`backup_immich_library_dir`） | ディレクトリを直接バックアップ |
| `app-db` | app ロールの PostgreSQL | `pg_dump` でダンプしてからバックアップ |

### 対象外（意図的に除外している）

| 対象 | 理由 |
| --- | --- |
| litellm の PostgreSQL | モデル定義を含むが、消失時は Web UI から手動再登録できるため受容する |
| langfuse の PostgreSQL・ClickHouse | LLM のトレースは消失しても許容するという判断 |
| traefik の `acme.json` | Let's Encrypt から再取得できる |
| portainer のデータ | 再設定できる |
| grafana のデータ | ダッシュボードは Git 管理下にあり、アラート履歴等は消失を許容する |

## 主要変数

| 変数 | 説明 |
| --- | --- |
| `backup_restic_version` / `backup_autorestic_version` | 取得するバイナリのバージョン。変更すると次回実行時に入れ替わる |
| `backup_retention_daily` | `forget --prune` で残す日次世代数。全 location 共通 |
| `backup_cron_hour` / `backup_cron_minute` | cron の実行時刻 |
| `backup_dump_dir` | ダンプの一時置き場。バックアップ対象パスでもある |
| `backup_immich_db_*` / `backup_app_db_*` | `pg_dump` 実行時のコンテナ名・DB ユーザー・DB 名 |
| `backup_aws_region` | S3 バックエンドのリージョン |

具体的な値は `defaults/main.yml` を参照。

### Vault 変数

`vars/vault.yml`（Ansible Vault 暗号化）に以下を定義する。

- `backup_vault_s3_bucket` — バックアップ先の S3 バケット名
- `backup_vault_aws_access_key_id` — S3 アクセスキー ID
- `backup_vault_aws_secret_access_key` — S3 シークレットアクセスキー
- `backup_vault_restic_password` — restic リポジトリの暗号化パスワード

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make backup` |
| 開発機 | `make deploy-backup` |

Vault パスワードが必要（Makefile のターゲットに `--ask-vault-pass` 組み込み済み）。sudo パスワードは不要。
ハンドラは持たない（`handlers/main.yml` は空）。`.autorestic.yml` と `backup.sh` はタスクで直接配置され、次回の cron 実行から新しい内容が使われる。

運用コマンドは以下のとおり。

| コマンド | 内容 |
| --- | --- |
| `make backup-status` / `make deploy-backup-status` | S3 リポジトリの疎通、スナップショット一覧、cron 登録状況 |
| `make backup-run` / `make deploy-backup-run` | バックアップを手動実行 |
| `journalctl -t autorestic-backup` | 実行ログの確認 |

## 運用上の注意

- **restic パスワードを失うと全バックアップが復元不能になる**。`backup_vault_restic_password` は暗号化の鍵そのものであり、S3 上のデータは restic 以外の手段では読めない。vault が失われた場合に備え、vault とは別の場所（パスワードマネージャ等）にも保管しておくこと
- **ダンプファイルは毎回削除される**。`backup.sh` は EXIT trap で `/opt/backup/dumps/` 配下のダンプを削除するため、実行後にホスト上へダンプは残らない。Immich のアップグレード前など手元にダンプを残したい場合は、`docker exec` で別名のファイルへ手動取得すること
- **syslog タグ `autorestic-backup` を変更しない**。Grafana のバックアップ監視アラートはこのタグと、`backup.sh` が出力する `Backup failed` / `Backup completed successfully` という文字列に依存している。タグやメッセージを変えると、失敗検知と「一定時間バックアップが成功していない」検知の両方が無言で壊れる
- **backup 用の S3 バケットと IAM ユーザーは tofu 管理外**（手動作成）。`tofu/` が管理しているのは langfuse 用のバケットのみ。バケット名も vault 変数のため、Git 上には現れない
- **バイナリは GitHub Releases から取得し SHA256 で検証している**。バージョンを上げる際は `defaults/main.yml` の値だけを変更すればよい（チェックサムは同リリースの `SHA256SUMS` を参照するため追随不要）
- **バックアップ対象は 3 つだけ**という前提を崩さないこと。新しいサービスを追加したときは、上記「対象外」の表に理由付きで追記するか、location を追加するかを明示的に判断する
- **リストアの手順は [docs/backup-restore.md](../../../docs/backup-restore.md) を参照**。restic は空でないディレクトリへの復元を拒否するため、location ごとに一時ディレクトリへ復元してから本番パスへコピーする

## AWS IAM ポリシー（S3 バックアップ用）

backup ロールで使用する IAM ユーザーには、対象バケットへの読み書きのみ許可する最小権限ポリシーを推奨する。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::BUCKET_NAME",
                "arn:aws:s3:::BUCKET_NAME/*"
            ]
        }
    ]
}
```

> **Note:** `BUCKET_NAME` は実際の S3 バケット名に置き換えること。バケット側でもサーバーサイド暗号化（SSE-S3 または SSE-KMS）の有効化を推奨する。

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/backup-restore.md](../../../docs/backup-restore.md) — リストア手順
- [immich ロール](../immich/README.md) — バックアップ対象（DB・ライブラリ）
- [app ロール](../app/README.md) — バックアップ対象（DB）
- [observability ロール](../observability/README.md) — バックアップ失敗の監視アラート
