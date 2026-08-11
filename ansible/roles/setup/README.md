# setup ロール

Ubuntu Server の初期セットアップ（日本語化・DNS・Docker・共通ディレクトリ）を行うロール。

## 概要

新規サーバの構築時と、Docker デーモン設定を変更したときに実行する。コンテナは持たず、ホスト OS 側の設定のみを扱う。
site.yml のタグは `setup`。全タスクが `become: true` を伴い sudo パスワード（`--ask-become-pass`）を要するため、CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象外であり、適用は常に手動。

## 実行内容

| 区分 | 内容 |
| --- | --- |
| 日本語化 | `language-pack-ja` の導入、`ja_JP.UTF-8` ロケール生成、`/etc/default/locale` の `LANG` 設定、タイムゾーンを `Asia/Tokyo` に設定 |
| DNS | systemd-resolved のスタブリスナー無効化（`DNSStubListener=no`）、`/etc/resolv.conf` を `/run/systemd/resolve/resolv.conf` へのリンクに統一 |
| Docker | 公式 GPG キーとリポジトリの追加、docker-ce 一式（buildx・compose プラグイン含む）の導入、`/etc/docker/daemon.json` の配置、サービスの有効化・起動、実行ユーザーの `docker` グループ追加 |
| バックアップ依存 | `sqlite3`・`bzip2` の導入 |
| ディレクトリ | `/opt` 配下の各ロール用ディレクトリをログインユーザー所有で作成 |

ハンドラは「Systemd-resolved を再起動」「Docker を再起動」の 2 つ。

## 配置ファイル

| 配置先 | 生成元 | 備考 |
| --- | --- | --- |
| `/etc/docker/daemon.json` | `setup_docker_daemon_config`（`defaults/main.yml`）を JSON 化 | `templates/` は持たず、`copy` モジュールの `content` で生成する |

## 主要変数

| 変数 | 用途・設計意図 |
| --- | --- |
| `setup_docker_daemon_config` | `/etc/docker/daemon.json` の内容。`dns` にはホスト自身の IP（＝CoreDNS）を `ansible_facts` のデフォルトルート由来アドレスから解決して入れる。同じ値が coredns ロールの vault にもあるが、`make setup` は vault を復号しないため fact を使う |

### Vault 変数

なし。`--ask-vault-pass` は不要。代わりに `--ask-become-pass` が必須。

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make setup` |
| 開発機 | `make deploy-setup` |

sudo パスワードの入力を求められる。CD 対象外のため自動デプロイは走らない。
`/etc/docker/daemon.json` が変化するとハンドラで Docker デーモンが再起動し、`/etc/systemd/resolved.conf` または `/etc/resolv.conf` が変化すると systemd-resolved が再起動する。

## 運用上の注意

- `/etc/docker/daemon.json` の DNS 上流は**必ず CoreDNS（＝ホスト自身の IP）を指すこと。8.8.8.8 等の外部 DNS を直接指定してはならない**。`*.internal.kagiyama.net` は CoreDNS の hosts プラグインが返す内部専用レコードでパブリック DNS には存在せず、外部 DNS を直接指定すると内部ドメインを参照するコンテナ（django-api・celery-*・litellm-proxy 等）が名前解決できなくなる（PR #113 で実際に起こした障害）。CoreDNS なら内部レコードを hosts で返し、それ以外は forward で外部へ流すため双方を満たす。経緯は [docs/dns.md](../../../docs/dns.md) を参照
- **Docker デーモンの再起動は全コンテナの再起動を伴う**。daemon.json を変更する適用は全サービスの一時停止になるため、実行タイミングは利用者と合意してから行う
- CoreDNS がホストの 53 番ポートを使うため、systemd-resolved のスタブリスナー（`127.0.0.53:53`）を無効化している。この設定を戻すと CoreDNS のポートバインドが失敗する
- `/opt` 配下のロール用ディレクトリ作成はこのロールの担当で、各サービスロールの前提になっている。ただし**コンテナ側が所有権や中身を作るデータディレクトリ（Immich のライブラリ等）は作らない**。Compose の初回起動に任せること
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ（`localhost` への local 接続）。開発機で `ansible-playbook` を直接叩くと**開発機自身**が変更されるため、サーバへ適用する場合は必ず `make deploy-setup` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/dns.md](../../../docs/dns.md) — DNS 構成と daemon.json の設計判断
- [coredns ロール](../coredns/README.md) — 内部 DNS サーバ
- [test ロール](../test/README.md) — 疎通確認
