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

1. `pg_dump` で immich / app の PostgreSQL をダンプし `/opt/backup/dumps/{immich,app}/` に出力
2. `autorestic backup -a` で全 location（`immich-db` / `immich-library` / `app-db`）を S3 へバックアップ
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
```

復元先にはバックアップ時の絶対パス構造がそのまま展開される。

```bash
ls /tmp/restore-app/opt/backup/dumps/app/kawashiro.sql
ls /tmp/restore-immich-db/opt/backup/dumps/immich/immich.sql
ls /tmp/restore-immich-lib/opt/immich/library/
```

ダンプは末尾の完了マーカー（`PostgreSQL database dump complete`）まで確認する。

### 2. app データベースの戻し込み

コンテナ名・DB ユーザー名は `ansible/roles/backup/defaults/main.yml` の値。

```bash
# DB に書き込むコンテナを停止
docker stop django-api celery-worker celery-beat

# DB を作り直してダンプを流し込む
docker exec app-database psql -U kawashiro -d postgres -c 'DROP DATABASE IF EXISTS kawashiro WITH (FORCE);'
docker exec app-database psql -U kawashiro -d postgres -c 'CREATE DATABASE kawashiro OWNER kawashiro;'
docker exec -i app-database psql -U kawashiro -d kawashiro < /tmp/restore-app/opt/backup/dumps/app/kawashiro.sql

# 再開して動作確認
docker start django-api celery-worker celery-beat
docker ps --filter name=django-api    # healthy になること
```

### 3. immich データベースの戻し込み

```bash
docker stop immich-server immich-machine-learning

docker exec immich-database psql -U postgres -d postgres -c 'DROP DATABASE IF EXISTS immich WITH (FORCE);'
docker exec immich-database psql -U postgres -d postgres -c 'CREATE DATABASE immich;'
docker exec -i immich-database psql -U postgres -d immich < /tmp/restore-immich-db/opt/backup/dumps/immich/immich.sql

docker start immich-server immich-machine-learning
```

> **Note:** immich のダンプには拡張（ベクトル検索）の定義が含まれるため、必ず現行の immich-database
> コンテナ（カスタムイメージ）に対して復元すること。素の PostgreSQL には復元できない。

### 4. immich ライブラリ（写真・動画）の戻し込み

```bash
# immich-server を停止した状態で実施
sudo rsync -a /tmp/restore-immich-lib/opt/immich/library/ /opt/immich/library/
docker start immich-server
```

### 5. 事後確認

- Immich にログインし写真が表示されること
- kawashiro-server（`internal.kagiyama.net`）が応答すること
- 一時ディレクトリ（`/tmp/restore-*`）を削除

## restic パスワードの管理

- restic パスワードは `ansible/roles/backup/vars/vault.yml`（`backup_vault_restic_password`）にある
- **このパスワードを失うと全バックアップが復元不能になる**。vault とは別にパスワードマネージャ等での二重保管を必須とする
- vault パスワード自体の管理は [ansible/README.md](../ansible/README.md) を参照

## 関連ドキュメント

- [backup ロール README](../ansible/roles/backup/README.md) — 対象・対象外の一覧と理由、構成の詳細
- [docs/initial-setup.md](initial-setup.md) — 全損時の再構築手順（リストアの前段）
- [docs/troubleshooting.md](troubleshooting.md) — バックアップ失敗通知への対応
