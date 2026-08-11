# traefik ロール

リバースプロキシ Traefik と、Let's Encrypt 証明書の自動取得・更新を担うロール。

## 概要

`traefik-public` ネットワーク上のコンテナに付いた Traefik ラベルを Docker プロバイダで読み取り、HTTPS で公開する。証明書は Route 53 の DNS-01 チャレンジで取得する。
site.yml のタグは `traefik`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象で、`ansible/roles/traefik/` 配下の変更が main にマージされると自動デプロイされる。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `traefik` | `traefik`（タグは `defaults/main.yml` 参照） | 80、443 | HTTP から HTTPS へのリダイレクト、HTTPS 終端、ラベルに基づくルーティング |

Docker ソケットは読み取り専用でマウントし、`no-new-privileges`・`cap_drop: ALL` とメモリ・CPU・PID の上限を設定している。ダッシュボード（`api.dashboard`）は無効。
各サービスが `external: true` で参照する `traefik-public` ネットワークは、このロールが作成する。

## 配置ファイル

| 配置先 | テンプレート | 内容 |
| --- | --- | --- |
| `/opt/traefik/docker-compose.yml` | `templates/docker-compose.yml.j2` | コンテナ定義。AWS 認証情報を環境変数で渡すためパーミッションは `0600` |
| `/opt/traefik/traefik.yml` | `templates/traefik.yml.j2` | 静的設定（エントリポイント、Docker プロバイダ、ACME） |

証明書ストア `acme.json` は named volume `traefik_letsencrypt` 内（コンテナの `/letsencrypt`）に置かれる。

## 主要変数

| 変数 | 用途・設計意図 |
| --- | --- |
| `traefik_acme_resolvers` | DNS-01 チャレンジの伝播確認に使う DNS サーバ。CoreDNS がシステム DNS だと権威 NS の自動検出が妨害されるため、Route 53 の権威ネームサーバを**ハードコード**している |
| `traefik_acme_staging` | Let's Encrypt ステージング環境を使うか。初回の動作確認時のみ true にし、レート制限を消費しないようにする |
| `traefik_acme_email` | ACME 登録用メールアドレス。`defaults/main.yml` では空値で、`vars/vault.yml` 側で上書きする |
| `traefik_aws_region` | Route 53 API 呼び出しのリージョン |

伝播確認前の待機時間（`delayBeforeChecks`）は `templates/traefik.yml.j2` に直接書かれている。

### Vault 変数

- `traefik_vault_aws_access_key_id`
- `traefik_vault_aws_secret_access_key`

加えて `traefik_acme_email` を `vars/vault.yml` で上書きする前提になっている（`defaults/main.yml` のコメント参照）。

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make traefik` |
| 開発機 | `make deploy-traefik` |

Vault パスワード（`--ask-vault-pass`）が必要。sudo パスワードは不要。
`docker-compose.yml`・`traefik.yml` のいずれかが変化すると、ハンドラで Traefik コンテナが再起動する。証明書は named volume に残るため、再起動しても再取得は発生しない。

## AWS IAM ポリシー（Route 53 DNS-01 チャレンジ用）

証明書取得に使う IAM ユーザーには、Route 53 の TXT レコード操作のみ許可する最小権限ポリシーを推奨する。

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

## 運用上の注意

- `traefik_acme_resolvers` には Route 53 の権威ネームサーバを**ハードコード**している。Route 53 側で NS が変わると伝播確認が通らなくなり、証明書の更新が止まる。現在値は `dig +short NS <ホストゾーンのドメイン> @<外部リゾルバ>`（内部 DNS を経由しないよう外部へ直接問い合わせる）や AWS コンソールで確認し、差異があれば `defaults/main.yml` を更新する
- `acme.json` は named volume にあり**バックアップ対象外**（backup ロールが扱うのは Immich の DB・ライブラリと app の DB のみ）。証明書は再取得できるため許容しているが、Let's Encrypt のレート制限があるのでボリュームを消して取り直す運用にしないこと
- 証明書障害の調査は `docker logs traefik | grep -i acme` で更新失敗の**理由**を見るところから始める。理由が DNS だった場合、証明書や ACME 設定をいくら見ても原因に届かない。期限の実測は `openssl s_client -connect <FQDN>:443 </dev/null | openssl x509 -noout -enddate`。詳細は [docs/troubleshooting.md](../../../docs/troubleshooting.md)
- 更新は「期限まで 30 日以内」で走る。更新済みかどうかの判定はこの閾値に合わせること
- `traefik-public` ネットワークはこのロールが作るため、Traefik 未デプロイの環境では他ロールの `external: true` 参照が失敗する。新規構築時は setup → coredns → traefik → 各サービスの順に流す
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、サーバへ適用する場合は必ず `make deploy-traefik` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/dns.md](../../../docs/dns.md) — DNS 構成と ACME への干渉点
- [docs/troubleshooting.md](../../../docs/troubleshooting.md) — 証明書・名前解決の障害調査
- [coredns ロール](../coredns/README.md) — 内部 DNS サーバ
- [portainer ロール](../portainer/README.md) — Traefik 経由で公開するサービスの例
