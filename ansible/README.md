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
    ├── coredns/                 # CoreDNS 内部DNSサーバ
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（機密情報を含まない）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、DNSレコード等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── docker-compose.yml.j2
    │       ├── Corefile.j2
    │       └── custom.hosts.j2
    ├── portainer/               # Portainer Docker管理UI
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、ポート等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       └── docker-compose.yml.j2
    ├── traefik/                 # Traefik リバースプロキシ
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、ポート等）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、AWS認証情報等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── docker-compose.yml.j2
    │       └── traefik.yml.j2   # Traefik 静的設定
    └── immich/                  # Immich 写真・動画管理
        ├── defaults/
        │   └── main.yml         # デフォルト変数（イメージ、ポート等）
        ├── vars/
        │   └── vault.yml        # 機密変数（Vault暗号化、DBパスワード等）
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        └── templates/
            ├── docker-compose.yml.j2
            └── env.j2           # 環境変数ファイル
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

内部IPアドレスやホスト名などの機密情報は各ロールの `vars/main.yml` に定義し、Ansible Vault で暗号化して管理する。
`group_vars` ではなくロール内の `vars/` に配置することで、該当ロール実行時のみ Vault パスワードが必要になる。

### 初回の暗号化

```bash
cd ansible
ansible-vault encrypt roles/coredns/vars/vault.yml
```

### 変数の編集

```bash
cd ansible
ansible-vault edit roles/coredns/vars/vault.yml
```

復号 → エディタで編集 → 保存時に再暗号化が自動で行われる。

### よく使うコマンド

| コマンド                       | 用途                         |
| ------------------------------ | ---------------------------- |
| `ansible-vault encrypt <file>` | 平文ファイルを暗号化         |
| `ansible-vault edit <file>`    | 復号して編集→再暗号化        |
| `ansible-vault view <file>`    | 復号して閲覧（読み取り専用） |
| `ansible-vault decrypt <file>` | 暗号化ファイルを平文に戻す   |

### プレイブック実行時

Vault を使用するロール（CoreDNS 等）の実行時は `--ask-vault-pass` が必要。Makefile のターゲットには組み込み済み。

```bash
make coredns  # Vault パスワードの入力を求められる
```

> **Note:** Portainer ロールは Vault を使用しないため、`make portainer` でそのまま実行できる。

### AWS IAM ポリシー（Route 53 DNS-01 チャレンジ用）

Traefik の Let's Encrypt 証明書取得に使用する IAM ユーザーには、Route 53 の TXT レコード操作のみ許可する最小権限ポリシーを推奨する。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetChange",
                "route53:ChangeResourceRecordSets",
                "route53:ListResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/ZXXXXXXXXXX"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetChange"
            ],
            "Resource": "arn:aws:route53:::change/*"
        },
        {
            "Effect": "Allow",
            "Action": "route53:ListHostedZonesByName",
            "Resource": "*"
        }
    ]
}
```

> **Note:** `hostedzone/ZXXXXXXXXXX` は実際の Hosted Zone ID に置き換えること。特定のゾーンに限定することで、他のゾーンへの操作を防止できる。
