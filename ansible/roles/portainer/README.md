# portainer ロール

Docker 管理 UI の Portainer CE をデプロイするロール。

## 概要

稼働中のコンテナ・ログ・ボリュームをブラウザから確認するための管理 UI。FQDN は `ansible/group_vars/local.yml` の `portainer_traefik_host`（`portainer.internal.kagiyama.net`）。
site.yml のタグは `portainer`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象で、`ansible/roles/portainer/` 配下の変更が main にマージされると自動デプロイされる。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `portainer` | `portainer/portainer-ce`（タグは `defaults/main.yml` 参照） | 9000（HTTP）、9443（HTTPS） | Docker 管理 UI |

Traefik のルーティング先は 9000。9443 は `portainer_bind_address` に指定したアドレスにのみ公開する。Docker ソケットは読み取り専用でマウントし、`no-new-privileges`・`cap_drop: ALL` とメモリ・CPU・PID の上限を設定している。

## 配置ファイル

| 配置先 | テンプレート | 内容 |
| --- | --- | --- |
| `/opt/portainer/docker-compose.yml` | `templates/docker-compose.yml.j2` | コンテナ定義（Traefik ルータのラベルを含む） |

`/opt/portainer` は setup ロールで作成済みであることが前提。データは named volume `portainer_data`（コンテナの `/data`）に保存される。

## 主要変数

| 変数 | 用途・設計意図 |
| --- | --- |
| `portainer_bind_address` | 9443 を公開するアドレス。既定を `127.0.0.1` にして LAN からの直接アクセスを塞ぎ、公開経路を Traefik のみに限定している |
| `portainer_https_port` | ホスト側で公開するポート番号 |

FQDN の `portainer_traefik_host` とネットワーク名の `traefik_network_name` は `ansible/group_vars/local.yml` で他ロールと共有する。

### Vault 変数

なし。`--ask-vault-pass` は不要。

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make portainer` |
| 開発機 | `make deploy-portainer` |

Vault パスワード・sudo パスワードのいずれも不要。
`docker-compose.yml` が変化すると、ハンドラで Portainer コンテナが再起動する。

## 運用上の注意

- サービスロールのうち**Vault を使わないのはこのロールだけ**で、その例外が 2 箇所に実装されている。ルート `Makefile` の `portainer` ターゲットには `--ask-vault-pass` が無く、`.github/workflows/deploy.yml` のデプロイスクリプトにも `portainer` だけ `--vault-password-file` を渡さない分岐がある。このロールに vault 変数を導入するなら**両方の修正が必要**で、片方だけだとローカル実行か CD のどちらかが失敗する
- Portainer のデータは named volume `portainer_data` にあり**バックアップ対象外**（backup ロールが扱うのは Immich の DB・ライブラリと app の DB のみ）。UI 上で作った設定は失われると復元できないため、恒久的な構成は Ansible 側に持たせること
- 9443 は既定で `127.0.0.1` にのみ公開している。ホスト外から直接アクセスできないのは意図どおりで、外部からは Traefik 経由の HTTPS のみ。ホスト上での切り分けには `curl -k https://127.0.0.1:9443` を使う
- ルーティングとネットワーク（`traefik-public`）は traefik ロールに依存する。Traefik 未デプロイの環境ではコンテナ起動時に外部ネットワークの参照が失敗する
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、サーバへ適用する場合は必ず `make deploy-portainer` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [traefik ロール](../traefik/README.md) — リバースプロキシと証明書
- [coredns ロール](../coredns/README.md) — FQDN の名前解決
