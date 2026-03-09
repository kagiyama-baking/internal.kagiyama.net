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
│   └── local.yml                # localグループの変数定義（Vault暗号化）
└── roles/
    ├── test/                    # テスト用ロール
    │   └── tasks/
    │       └── main.yml
    ├── setup/                   # セットアップロール（Docker等）
    │   └── tasks/
    │       └── main.yml
    └── coredns/                 # CoreDNS 内部DNSサーバ
        ├── defaults/
        │   └── main.yml         # デフォルト変数（機密情報を含まない）
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

## Ansible Vault

内部IPアドレスやホスト名などの機密情報は `group_vars/local.yml` に定義し、Ansible Vault で暗号化して管理する。

### 初回の暗号化

```bash
cd ansible
ansible-vault encrypt group_vars/local.yml
```

### 変数の編集

```bash
ansible-vault edit group_vars/local.yml
```

復号 → エディタで編集 → 保存時に再暗号化が自動で行われる。

### よく使うコマンド

| コマンド | 用途 |
|----------|------|
| `ansible-vault encrypt <file>` | 平文ファイルを暗号化 |
| `ansible-vault edit <file>` | 復号して編集→再暗号化 |
| `ansible-vault view <file>` | 復号して閲覧（読み取り専用） |
| `ansible-vault decrypt <file>` | 暗号化ファイルを平文に戻す |

### プレイブック実行時

Vault を使用するロール（CoreDNS 等）の実行時は `--ask-vault-pass` が必要。Makefile のターゲットには組み込み済み。

```bash
make coredns  # Vault パスワードの入力を求められる
```
