i# Ansible

自宅サーバ（Ubuntu Server 22.04.4）の構成管理を行うAnsibleプレイブック。

## ディレクトリ構成

```
ansible/
├── Makefile                     # 実行用Makefile
├── ansible.cfg                  # Ansible設定ファイル
├── site.yml                     # サイトプレイブック（エントリポイント）
├── inventories/
│   └── local/
│       └── hosts                # ローカル実行用インベントリ
├── group_vars/
│   └── local.yml                # localグループの変数定義
└── roles/
    ├── test/                    # テスト用ロール
    │   └── tasks/
    │       └── main.yml
    └── setup/                   # セットアップロール（Docker等）
        └── tasks/
            └── main.yml
```

## 使い方

Makefileを使って実行する。

| コマンド | 内容 |
|---|---|
| `make test` | テスト用プレイブックを実行 |
| `make setup` | セットアップ（Docker等のインストール） |
| `make all` | すべて実行 |
| `make check` | ドライラン（変更を適用せずに確認） |

## ロールの追加方法

1. `roles/` 配下に新しいロールディレクトリを作成する

    ```
    roles/<ロール名>/
    ├── tasks/
    │   └── main.yml
    ├── handlers/       # 必要に応じて
    │   └── main.yml
    ├── templates/      # 必要に応じて
    ├── files/          # 必要に応じて
    └── defaults/       # 必要に応じて
        └── main.yml
    ```

2. `site.yml` の `roles` に追加する

    ```yaml
    roles:
        - <ロール名>
    ```
