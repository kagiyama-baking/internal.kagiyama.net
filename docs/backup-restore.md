# バックアップとリストア

[autorestic](https://autorestic.vercel.app/)（[restic](https://restic.net/) のラッパー）でサーバ上の重要データを AWS S3 に自動バックアップしている。
この文書は仕組み・日常運用・リストア（復旧）の実手順をまとめる。
バックアップの**対象・対象外とその理由**は [backup ロール README](../ansible/roles/backup/README.md) を参照。

## 概要

| 項目 | 内容 |
|---|---|
| スケジュール | 毎日 03:00（cron。時刻は `ansible/roles/backup/defaults/main.yml` 参照） |
| 保存先 | AWS S3（バケット名は vault 管理） |
| リテンション | 日次 7 世代（`backup_retention_daily`） |
| 暗号化 | restic による暗号化（パスワードは vault 管理） |
| ログ | syslog タグ `autorestic-backup`（Grafana のバックアップ監視アラートがこのタグに依存） |

## 仕組み

cron が `/opt/backup/backup.sh` を実行する。流れ:

1. `pg_dump` で immich / app / langfuse の PostgreSQL をダンプし `/opt/backup/dumps/{immich,app,langfuse}/` に出力
2. `autorestic backup -a` で全 location（`immich-db` / `immich-library` / `app-db` / `langfuse-db`）を S3 へバックアップ
3. `autorestic forget -a --prune` で保持世代を超えたスナップショットを削除
4. **EXIT trap がダンプファイルを削除する（成功・失敗を問わず）**

ダンプを手元に残したい場合（Immich メジャーアップグレード前など）は、trap の対象にならない別名で手動取得すること（例: `~/immich-pre-upgrade-YYYYMMDD.sql`）。

## 手動実行・状態確認

```bash
# バックアップを手動実行
make backup-run          # サーバ上
make deploy-backup-run   # 開発機から

# 状態確認（リポジトリ整合性・スナップショット一覧・cron 登録）
make backup-status          # サーバ上
make deploy-backup-status   # 開発機から

# ログ確認（syslog に出力される）
journalctl -t autorestic-backup
```

## リストア

### 前提と注意

- **リストアは破壊的操作**。必ず一時ディレクトリへ復元し、内容を確認してから本番へ反映する
- vault パスワード（設定変更を伴う場合）と S3 への接続情報は `/opt/backup/.autorestic.yml` に設定済み（backup ロールがデプロイ済みであること）
- restic は空でないディレクトリへの直接リストアを拒否するため、location ごとに別ディレクトリへ復元する
- `autorestic restore` は最新スナップショットを復元する。特定時点への復元は `restic` を直接使う（[restic ドキュメント](https://restic.readthedocs.io/)参照）

### 1. 一時ディレクトリへ復元

```bash
cd /opt/backup

PATH=/opt/backup/bin:$PATH autorestic restore -l app-db -c .autorestic.yml --to /tmp/restore-app
PATH=/opt/backup/bin:$PATH autorestic restore -l immich-db -c .autorestic.yml --to /tmp/restore-immich-db
PATH=/opt/backup/bin:$PATH autorestic restore -l immich-library -c .autorestic.yml --to /tmp/restore-immich-lib
PATH=/opt/backup/bin:$PATH autorestic restore -l langfuse-db -c .autorestic.yml --to /tmp/restore-langfuse-db
```

復元先にはバックアップ時の絶対パス構造がそのまま展開される。

```bash
ls /tmp/restore-app/opt/backup/dumps/app/kawashiro.sql
ls /tmp/restore-immich-db/opt/backup/dumps/immich/immich.sql
ls /tmp/restore-immich-lib/opt/immich/library/
ls /tmp/restore-langfuse-db/opt/backup/dumps/langfuse/langfuse.sql
```

ダンプは末尾の完了マーカー（`PostgreSQL database dump complete`）まで確認する。

### 2. app データベースの戻し込み

コンテナ名・DB ユーザー名は `ansible/roles/backup/defaults/main.yml` の値。

各段階を `&&` でつなぎ、途中で失敗したら次へ進まない（失敗したまま再開すると、空の DB で起動してしまう）。

```bash
# ダンプの完了マーカーを確かめてから、DB に書き込むコンテナを停止し、DB を作り直してダンプを流し込み、再開する
tail -n 5 /tmp/restore-app/opt/backup/dumps/app/kawashiro.sql | grep -q 'PostgreSQL database dump complete' \
  && docker stop django-api celery-worker celery-beat \
  && docker exec app-database psql -U kawashiro -d postgres -c 'DROP DATABASE IF EXISTS kawashiro WITH (FORCE);' \
  && docker exec app-database psql -U kawashiro -d postgres -c 'CREATE DATABASE kawashiro OWNER kawashiro;' \
  && docker exec -i app-database psql -U kawashiro -d kawashiro -v ON_ERROR_STOP=1 < /tmp/restore-app/opt/backup/dumps/app/kawashiro.sql \
  && docker start django-api celery-worker celery-beat
docker ps --filter name=django-api    # healthy になること
```

### 3. immich データベースの戻し込み

```bash
tail -n 5 /tmp/restore-immich-db/opt/backup/dumps/immich/immich.sql | grep -q 'PostgreSQL database dump complete' \
  && docker stop immich-server immich-machine-learning \
  && docker exec immich-database psql -U postgres -d postgres -c 'DROP DATABASE IF EXISTS immich WITH (FORCE);' \
  && docker exec immich-database psql -U postgres -d postgres -c 'CREATE DATABASE immich;' \
  && docker exec -i immich-database psql -U postgres -d immich -v ON_ERROR_STOP=1 < /tmp/restore-immich-db/opt/backup/dumps/immich/immich.sql \
  && docker start immich-server immich-machine-learning
```

> **Note:** immich のダンプには拡張（ベクトル検索）の定義が含まれるため、必ず現行の immich-database
> コンテナ（カスタムイメージ）に対して復元すること。素の PostgreSQL には復元できない。

### 4. immich ライブラリ（写真・動画）の戻し込み

```bash
# immich-server を停止した状態で実施
sudo rsync -a /tmp/restore-immich-lib/opt/immich/library/ /opt/immich/library/
docker start immich-server
```

### 5. langfuse データベースの戻し込み

戻るのはトレース以外の設定（プロジェクト・API キー・プロンプト等）。ClickHouse のトレースは対象外で、PostgreSQL 側の参照が消えた分は UI に出ないことがある。手元に取った別名のダンプ（本体の更新前の控えなど）を戻すときも、パスを読み替えて同じ手順を使う。

```bash
tail -n 5 /tmp/restore-langfuse-db/opt/backup/dumps/langfuse/langfuse.sql | grep -q 'PostgreSQL database dump complete' \
  && docker stop langfuse-web langfuse-worker \
  && docker exec langfuse-database psql -U langfuse -d postgres -c 'DROP DATABASE IF EXISTS langfuse WITH (FORCE);' \
  && docker exec langfuse-database psql -U langfuse -d postgres -c 'CREATE DATABASE langfuse OWNER langfuse;' \
  && docker exec -i langfuse-database psql -U langfuse -d langfuse -v ON_ERROR_STOP=1 < /tmp/restore-langfuse-db/opt/backup/dumps/langfuse/langfuse.sql \
  && docker start langfuse-web langfuse-worker
docker ps --filter name=langfuse-web    # healthy になること
```

> **Note:** ダンプと Langfuse 本体の版を揃えること。古いダンプを新しい版に流し込むと、起動時の migration が再度走る。本体の更新と同時の切り戻しは [langfuse ロール README](../ansible/roles/langfuse/README.md) の手順に従う。

### 6. 事後確認

- Immich にログインし写真が表示されること
- kawashiro-server（`internal.kagiyama.net`）が応答すること
- Langfuse にログインしプロンプトが表示されること
- 一時ディレクトリ（`/tmp/restore-*`）を削除

## restic パスワードの管理

- restic パスワードは `ansible/roles/backup/vars/vault.yml`（`backup_vault_restic_password`）にある
- **このパスワードを失うと全バックアップが復元不能になる**。vault とは別にパスワードマネージャ等での二重保管を必須とする
- vault パスワード自体の管理は [ansible/README.md](../ansible/README.md) を参照

## 関連ドキュメント

- [backup ロール README](../ansible/roles/backup/README.md) — 対象・対象外の一覧と理由、構成の詳細
- [docs/initial-setup.md](initial-setup.md) — 全損時の再構築手順（リストアの前段）
- [docs/troubleshooting.md](troubleshooting.md) — バックアップ失敗通知への対応
