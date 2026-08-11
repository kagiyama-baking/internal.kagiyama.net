# immich ロール

セルフホスト型の写真・動画管理サービス Immich をデプロイするロール。

## 概要

Immich 本体・機械学習・Redis（Valkey）・PostgreSQL の 4 コンテナを Docker Compose で起動し、Traefik 経由で HTTPS 公開する。
公開 FQDN は `immich_traefik_host`（`ansible/group_vars/local.yml`）で定義する。site.yml のタグは `immich`。
CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象であり、`ansible/roles/immich/` の変更が main にマージされると自動デプロイされる。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `immich-server` | `ghcr.io/immich-app/immich-server` | 2283 | Web UI と API。Traefik のルーティング先 |
| `immich-machine-learning` | `ghcr.io/immich-app/immich-machine-learning` | — | 顔認識・スマート検索の推論。モデルは `immich-model-cache` ボリュームにキャッシュ |
| `immich-redis` | `docker.io/valkey/valkey` | 6379 | ジョブキュー |
| `immich-database` | `ghcr.io/immich-app/postgres` | 5432 | メタデータとベクトル検索インデックス |

イメージのタグは `defaults/main.yml` を参照。
`immich-server` のみ `traefik_network_name` と `immich-internal` の両方に属し、残る 3 つは `immich-internal` のみに閉じる。
`immich-server` のホストポートは `immich_bind_address`（既定はループバック）に bind するため、外部から直接到達できるのは Traefik 経由のみ。
全コンテナで `cap_drop: ALL` と `no-new-privileges` を適用し、必要な capability だけを `cap_add` で戻している。

## 配置ファイル

| 配置先 | テンプレート | 権限 | 内容 |
| --- | --- | --- | --- |
| `/opt/immich/.env` | `templates/env.j2` | 0600 | DB 認証情報、DB/Redis のホスト名、タイムゾーン |
| `/opt/immich/docker-compose.yml` | `templates/docker-compose.yml.j2` | 0600 | 4 コンテナの定義 |

データ用ディレクトリ（`immich_upload_location`＝メディア実体、`immich_db_data_location`＝PostgreSQL データ）は Ansible では作成しない。
PostgreSQL がデータディレクトリの所有権をコンテナ UID に変更するため、Ansible で作ると再デプロイ時の `chmod` が EPERM で失敗する。Compose の初回起動に任せる。

## 主要変数

| 変数 | 設計・運用上の意図 |
| --- | --- |
| `immich_upload_location` | メディアの実体パス。コンテナ側のマウント先は変更厳禁（後述） |
| `immich_db_image` | ベクトル拡張入りの Immich 公式 PostgreSQL。素の `postgres` イメージへ差し替えると検索インデックスを失い起動できない |
| `immich_bind_address` | ホストポートの bind 先。Traefik 経由のみに限定する意図で、ループバックを既定とする |
| `immich_server_mem_limit` / `immich_ml_mem_limit` ほか | コンテナ単位のメモリ・CPU 上限。機械学習はモデルをメモリに載せるため最も大きく取っている |

### Vault 変数

`vars/vault.yml`（ansible-vault で暗号化）に以下を保持する。

- `immich_vault_db_password`

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make immich` |
| 開発機 | `make deploy-immich` |

Vault パスワードが必要（`--ask-vault-pass`）。sudo パスワードは不要。
`.env` または `docker-compose.yml` に差分が出るとハンドラ `Immich を再起動` が発火し、Compose プロジェクト全体が `state: restarted` で再起動する。
コンテナ起動タスクは `pull: missing` のため、**ローカルに同名タグが既にある場合はイメージを取得し直さない**。タグを変えずに中身だけ更新されたイメージへ追従したいときは、手動で `docker compose pull` を実行する。

## 運用上の注意

- **メジャーバージョンアップの手順**（過去のメジャー更新の実績に基づく）
    1. 公式リリースノートの破壊的変更を「読む」だけで終わらせず、**自環境の実値と 1 件ずつ突き合わせる**。DB 拡張は `SELECT extname FROM pg_extension`、CPU 命令セット要件は `/proc/cpuinfo`、削除された環境変数は `templates/env.j2` に無いこと、削除された API は外部ツール（immich-go 等）を使っていないこと、をそれぞれ確認する
    2. 公式の `docker-compose.yml` と `example.env` を新旧バージョンで取得し、現行テンプレートと diff を取る。リリースノートを何本も読むより速く「何を変える必要があるか」に到達できる
    3. `docker manifest inspect <image>:<tag>` で新タグの実在を pull せずに確認する。過去にタグ誤りで追加修正 PR を出した経緯がある
    4. 事前 DB ダンプを取得する。`backup.sh` の後始末は `immich.sql` / `kawashiro.sql` を EXIT trap で削除するため、**その名前では手元に残らない**。`~/immich-pre-v3-YYYYMMDD.sql` のような別名で取ること。取得後は完了マーカー `PostgreSQL database dump complete` と主要テーブルの行数一致まで検証する
    5. 実際の変更は `defaults/main.yml` のイメージタグ 2 行（server と machine-learning）で済むことが多い。DB・Redis のタグまで巻き込まない
- **メディアのマウント先 `/usr/src/app/upload` は変更厳禁**。公式 compose は `/data` へ移行済みだが、本リポジトリは旧来のパスを使い続けている。ここを「近代化」すると DB 内の全ファイルパスを書き換える自動マイグレーションが走り、不一致なら `InconsistentMediaLocation` で起動不能になる。バージョン更新と同時に行ってはならない。デプロイ後は `docker logs immich-server | grep -i "media location"` が **0 件**であることを確認する
- **ダウングレードは公式非対応**。スキーマ移行後の切り戻し手段は DB ダンプからの復元しかない。だからこそ上記 4 の事前ダンプが必須になる
- **DB は Immich 公式のベクトル拡張入りカスタムイメージ**であり、公式 `postgres` イメージへ差し替えることはできない
- **毎デプロイでコンテナが 2 回起動する**。タスクの `state: present` による再作成の直後に、テンプレート変更の notify で発火したハンドラが `state: restarted` でもう一度全コンテナを再起動するため。ログに起動が 2 回記録されるのは**仕様であり障害ではない**
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ（`localhost` への local 接続）。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、必ず `make deploy-immich` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/backup-restore.md](../../../docs/backup-restore.md) — バックアップと DB リストア手順
- [docs/troubleshooting.md](../../../docs/troubleshooting.md) — 障害調査の起点
- [traefik ロール](../traefik/README.md) — HTTPS 終端と証明書
- [backup ロール](../backup/README.md) — DB ダンプと S3 バックアップ
