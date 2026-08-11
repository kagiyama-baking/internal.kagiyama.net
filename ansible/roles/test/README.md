# test ロール

Ansible の接続と実行環境を確認するための疎通確認ロール。

## 概要

対象ホストへの疎通・ホスト名・OS バージョンを表示するだけのロールで、構成変更は一切行わない。
site.yml のタグは `test`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象外であり、自動デプロイされることはない。

## 実行内容

| タスク | モジュール | 目的 |
| --- | --- | --- |
| Ansible の動作確認 | `ansible.builtin.ping` | 接続と Python インタプリタの疎通確認 |
| ホスト名を取得・表示 | `ansible.builtin.command`（`hostname`）＋ `debug` | 適用先ホストの確認 |
| OS バージョンを取得・表示 | `ansible.builtin.command`（`lsb_release -d`）＋ `debug` | ディストリビューションの確認 |

コマンド実行タスクには `changed_when: false` を指定しており、常に changed=0 で終了する。

## 主要変数

なし。`defaults/`・`vars/`・`templates/`・`handlers/` を持たず、`tasks/main.yml` のみで構成される。

### Vault 変数

なし。`--ask-vault-pass` は不要。

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make test` |
| 開発機 | `make deploy-test` |

Vault パスワード・sudo パスワードのいずれも不要。CD 対象外のため実行は常に手動。

## 運用上の注意

- 疎通確認専用。新しいサーバの導入直後や SSH 設定の変更後、`make deploy-*` を流す前の事前チェックに使う
- `lsb_release` に依存するため Ubuntu（Debian 系）を前提とする。同コマンドが無い OS ではタスクが失敗する
- CD 対象外。`ansible/roles/test/` を変更しても自動デプロイは走らない
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ（`localhost` への local 接続）。開発機で `ansible-playbook` を直接叩くと**開発機自身**に対して実行されるため、サーバへ適用する場合は必ず `make deploy-test` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [setup ロール](../setup/README.md) — サーバ初期セットアップ
