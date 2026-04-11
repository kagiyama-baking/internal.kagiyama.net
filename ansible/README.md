# Ansible

`internal.kagiyama.net`の構成管理を行うAnsibleプレイブック。

## ディレクトリ構成

```
ansible/
├── ansible.cfg                  # Ansible設定ファイル
├── site.yml                     # サイトプレイブック（エントリポイント）
├── requirements.yml             # Ansibleコレクション定義（community.general, community.docker, ansible.posix）
├── inventories/
│   └── local/
│       └── hosts                # ローカル実行用インベントリ
├── group_vars/
│   └── local.yml                # localグループの変数定義（Traefikネットワーク名・サービスFQDNなど複数ロール共有変数）
└── roles/
    ├── test/                    # テスト用ロール
    │   └── tasks/
    │       └── main.yml
    ├── setup/                   # セットアップロール（Docker等）
    │   └── tasks/
    │       └── main.yml
    ├── coredns/                 # CoreDNS 内部DNSサーバ
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、TTL等）
    │   ├── vars/
    │   │   ├── main.yml         # DNSレコード定義（ホスト名平文、IPはvault参照）
    │   │   └── vault.yml        # 機密変数（Vault暗号化、IPアドレスのみ）
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
    ├── immich/                  # Immich 写真・動画管理
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、ポート等）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、DBパスワード等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── docker-compose.yml.j2
    │       └── env.j2           # 環境変数ファイル
    ├── app/                     # kawashiro-server Django REST API
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、ポート等）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、Djangoシークレット等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── docker-compose.yml.j2
    │       └── env.j2
    ├── litellm/                 # LiteLLM LLMプロバイダー抽象化プロキシ
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、ポート、リソース制限等）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、DBパスワード・マスターキー・Langfuse認証等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── docker-compose.yml.j2
    │       └── config.yaml.j2   # LiteLLM Proxy 設定（Langfuseトレース連携）
    ├── langfuse/                # LangFuse LLMオブザーバビリティ
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（イメージ、S3バケット、リソース制限等）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、DBパスワード・暗号化キー・S3認証等）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── docker-compose.yml.j2
    │       ├── env.j2           # 環境変数ファイル
    │       └── clickhouse/
    │           ├── config.d/
    │           │   ├── memory.xml.j2    # ClickHouse メモリチューニング
    │           │   └── logging.xml.j2   # システムテーブル TTL
    │           └── users.d/
    │               └── memory.xml.j2    # ユーザーメモリ制限
    ├── backup/                  # 自動バックアップ（autorestic → AWS S3）
    │   ├── defaults/
    │   │   └── main.yml         # デフォルト変数（バージョン、パス、リテンション等）
    │   ├── vars/
    │   │   └── vault.yml        # 機密変数（Vault暗号化、AWS認証・resticパスワード）
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       ├── autorestic.yml.j2  # autorestic 設定
    │       └── backup.sh.j2      # バックアップ実行スクリプト
    └── observability/           # Observability（Grafana, Prometheus, Loki等）
        ├── defaults/
        │   └── main.yml         # デフォルト変数（イメージ、リソース制限等）
        ├── vars/
        │   └── vault.yml        # 機密変数（Vault暗号化、Grafana管理者パスワード）
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        ├── templates/
        │   ├── docker-compose.yml.j2
        │   ├── prometheus.yml.j2
        │   ├── loki.yml.j2
        │   ├── promtail.yml.j2
        │   ├── grafana.env.j2     # Grafana 環境変数
        │   └── grafana/
        │       ├── datasources.yml.j2
        │       └── dashboards.yml.j2
        └── files/
            └── dashboards/
                ├── host-container-resources.json
                └── log-viewer.json
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

2. `site.yml` にプレイを追加する

    ```yaml
    - name: <ロール名> デプロイ
      hosts: local
      tags: <ロール名>
      roles:
          - <ロール名>
    ```

## 共有変数（group_vars/local.yml）

複数ロールで共通して使用する変数は `group_vars/local.yml` を Single Source of Truth として管理する。
現在定義されている変数：

| 変数名 | 値 | 用途 |
|---|---|---|
| `traefik_network_name` | `traefik-public` | Traefikネットワーク名（複数ロール共有） |
| `portainer_traefik_host` | `portainer.internal.kagiyama.net` | PortainerのFQDN（CoreDNS・Traefik共用） |
| `immich_traefik_host` | `immich.internal.kagiyama.net` | ImmichのFQDN（CoreDNS・Traefik共用） |
| `grafana_traefik_host` | `grafana.internal.kagiyama.net` | GrafanaのFQDN（CoreDNS・Traefik共用） |
| `app_traefik_host` | `internal.kagiyama.net` | kawashiro-serverのFQDN（CoreDNS・Traefik共用） |
| `litellm_traefik_host` | `litellm.internal.kagiyama.net` | LiteLLMのFQDN（CoreDNS・Traefik共用） |
| `langfuse_traefik_host` | `langfuse.internal.kagiyama.net` | LangFuseのFQDN（CoreDNS・Traefik共用） |

ホスト名を変更する際はこのファイルのみを編集すれば全ロールに反映される。

## Ansible Vault

IPアドレス等の機密情報は各ロールの `vars/vault.yml` に `<ロール名>_vault_` プレフィックス変数として定義し、Ansible Vault で暗号化して管理する。
ホスト名など機密でない設定は `vars/main.yml` に平文で定義し、vault 変数を参照する形にすることで、ホスト名の編集に vault 復号が不要になる。
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

### AWS IAM ポリシー（S3 バックアップ用）

backup ロールで使用する IAM ユーザーには、対象バケットへの読み書きのみ許可する最小権限ポリシーを推奨する。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::BUCKET_NAME",
                "arn:aws:s3:::BUCKET_NAME/*"
            ]
        }
    ]
}
```

> **Note:** `BUCKET_NAME` は実際の S3 バケット名に置き換えること。バケット側でもサーバーサイド暗号化（SSE-S3 または SSE-KMS）の有効化を推奨する。

### AWS IAM ポリシー（LangFuse S3 用）

langfuse ロールで使用する IAM ユーザーには、LangFuse 用 S3 バケット 3 つ（event, media, export）への読み書きのみ許可する最小権限ポリシーを推奨する。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::LANGFUSE_EVENT_BUCKET",
                "arn:aws:s3:::LANGFUSE_EVENT_BUCKET/*",
                "arn:aws:s3:::LANGFUSE_MEDIA_BUCKET",
                "arn:aws:s3:::LANGFUSE_MEDIA_BUCKET/*",
                "arn:aws:s3:::LANGFUSE_EXPORT_BUCKET",
                "arn:aws:s3:::LANGFUSE_EXPORT_BUCKET/*"
            ]
        }
    ]
}
```

> **Note:** バケット名は実際の値に置き換えること。このポリシーは `tofu/` の OpenTofu で自動プロビジョニングされるため、手動作成は通常不要。
