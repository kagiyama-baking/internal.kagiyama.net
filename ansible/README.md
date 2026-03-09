# Ansible

`internal.kagiyama.net`の構成管理を行うAnsibleプレイブック。

## ディレクトリ構成

```
ansible/
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
    ├── setup/                   # セットアップロール（Docker等）
    │   └── tasks/
    │       └── main.yml
    └── coredns/                 # CoreDNS 内部DNSサーバ
        ├── defaults/
        │   └── main.yml         # 変数定義（DNSレコード、上流DNS等）
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        └── templates/
            ├── docker-compose.yml.j2
            ├── Corefile.j2
            └── custom.hosts.j2
```

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
