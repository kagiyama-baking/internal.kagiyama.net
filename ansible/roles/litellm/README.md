# litellm ロール

複数の LLM プロバイダーを OpenAI 互換 API に集約する LiteLLM Proxy をデプロイするロール。

## 概要

LiteLLM Proxy と専用 PostgreSQL を Docker Compose で起動し、Traefik 経由で `litellm.internal.kagiyama.net`（`litellm_traefik_host`）に公開する。
site.yml のタグは `litellm`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象であり、`ansible/roles/litellm/` の変更が main にマージされると自動デプロイされる。
モデル定義は Git ではなく DB（Web UI）で管理する構成のため、「運用上の注意」を必ず読むこと。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `litellm-proxy` | `litellm/litellm` | 4000（`litellm_proxy_port`） | OpenAI 互換 API と Web UI（`/ui`）。Traefik 配下で公開 |
| `litellm-database` | `postgres` | 5432 | モデル定義・仮想 API キー・使用量ログの保存 |

イメージのタグは `defaults/main.yml` 参照（バージョン固定）。
ネットワークは Traefik 公開用（`traefik_network_name`／外部ネットワーク）と `litellm-internal` の 2 系統で、DB は内部ネットワークにのみ接続する。
両コンテナとも `cap_drop: ALL` ＋ `no-new-privileges` で起動し、DB のみ PostgreSQL の起動に必要な capability を個別に付与している。
Swagger UI / ReDoc は未認証での API 仕様露出を避けるため `NO_DOCS` / `NO_REDOC` で無効化している。

## 配置ファイル

| 配置先 | テンプレート | パーミッション |
| --- | --- | --- |
| `/opt/litellm/config.yaml` | `templates/config.yaml.j2` | 0644 |
| `/opt/litellm/docker-compose.yml` | `templates/docker-compose.yml.j2` | 0600 |
| `/opt/litellm/postgres/` | （PostgreSQL データボリューム） | — |

`/opt/litellm`（`litellm_install_dir`）はログインユーザー所有で setup ロールが作成済みであることが前提。

## 主要変数

| 変数 | 説明 |
| --- | --- |
| `litellm_store_model_in_db` | `True` でモデル定義を DB に保存し Web UI から管理する。この構成の前提となる最重要変数 |
| `litellm_langfuse_host` | トレース送信先の LangFuse URL。langfuse ロールの FQDN を指す |
| `litellm_db_data_location` | PostgreSQL のデータ永続化先。ここが失われるとモデル定義も失われる |
| `litellm_proxy_mem_limit` / `litellm_proxy_cpus` | Proxy のリソース上限 |
| `litellm_db_mem_limit` / `litellm_db_cpus` | DB のリソース上限 |

イメージタグ・ポート等の値は `defaults/main.yml` を参照。

### Vault 変数

`vars/vault.yml`（Ansible Vault 暗号化）に以下を定義する。

- `litellm_vault_master_key` — LiteLLM のマスターキー（`LITELLM_MASTER_KEY`）
- `litellm_vault_db_password` — PostgreSQL のパスワード
- `litellm_vault_langfuse_public_key` — LangFuse トレース送信用の公開キー
- `litellm_vault_langfuse_secret_key` — LangFuse トレース送信用の秘密キー

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make litellm` |
| 開発機 | `make deploy-litellm` |

Vault パスワードが必要（Makefile のターゲットに `--ask-vault-pass` 組み込み済み）。sudo パスワードは不要。
`config.yaml` または `docker-compose.yml` に差分が出るとハンドラ「LiteLLM を再起動」が走り、`litellm-proxy` と `litellm-database` の両方が `pull: always` 付きで再起動される。差分が無い場合もタスク側で `state: present` ＋ `pull: always` を実行するため、イメージタグを更新すれば新イメージが取得される。

## 運用上の注意

- **モデル定義は Git にもバックアップにも残らない**。`STORE_MODEL_IN_DB=True` によりモデルは Web UI から DB に登録され、`config.yaml` の `model_list` は空のまま運用する。`litellm-database` のデータ（`/opt/litellm/postgres`）は backup ロールの対象外であり、消失した場合は Web UI での手動再登録が必要になる。既知の受容済みリスクとして扱う
- **設定の優先順位は DB > `config.yaml`**。`config.yaml` に書いた設定が DB 側の値に上書きされ「効かない」ことがある。設定が反映されないときは、まず Web UI 側に同じ設定が存在しないかを疑う
- **`DATABASE_URL` に埋め込むパスワードは urlencode 必須**。`@` `:` `/` `#` `?` `&` `%` `+` などの URL 予約文字が含まれるとパーサーが壊れ、`P1013: invalid port number in database URL` のような原因の分かりにくいエラーになる。テンプレートでは URL に埋め込む箇所にのみ `urlencode` フィルタを適用しており、`POSTGRES_PASSWORD` には生の値を渡している。この非対称性を崩さないこと
- **healthcheck に `curl` / `wget` を使わない**。LiteLLM のコンテナイメージは Wolfi ベースで `curl` も `wget` も含まないため、これらを使う healthcheck は exit 127 で常に失敗し、Traefik が unhealthy な backend を除外して外部から 404 になる。同梱の `python3` ＋ `urllib.request` で liveliness を叩く実装にしてある
- **`config.yaml` は 0644 で配置している**。`cap_drop: ALL` ＋ `no-new-privileges` のコンテナでは root でも他ユーザー所有の 0600 ファイルを読めない（CAP_DAC_READ_SEARCH を失うため）。`config.yaml` はシークレットを含まない（master_key は環境変数参照、モデル定義は DB 管理）ので 0644 で問題ない。逆に、このファイルへシークレットを書き足してはならない
- **LangFuse へのトレース送信**は `config.yaml` の `success_callback` / `failure_callback` で有効化しており、認証キーは vault の `litellm_vault_langfuse_*` にある。LangFuse 側でキーをローテートしたら vault も更新すること
- **migration 不整合の履歴あり**。過去に、追加された `source_url` 列が後続 migration で drop される不整合があり、公式の復元 migration SQL を本番 DB へ手動適用して対処している。この適用は `_prisma_migrations` テーブルに登録されていないため、将来のアップグレード時に `prisma migrate resolve` が必要になる可能性がある。詳細は [docs/troubleshooting.md](../../../docs/troubleshooting.md) を参照

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/troubleshooting.md](../../../docs/troubleshooting.md) — 障害対応の記録
- [langfuse ロール](../langfuse/README.md) — トレース送信先
- [traefik ロール](../traefik/README.md) — リバースプロキシと TLS 終端
