# coredns ロール

内部 DNS サーバ CoreDNS をコンテナで動かすロール。

## 概要

`*.internal.kagiyama.net` の内部レコードを hosts プラグインで返し、それ以外の問い合わせは上流 DNS へ転送する。ホスト自身と全コンテナの DNS 上流がこの CoreDNS を指す。
site.yml のタグは `coredns`。CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象で、`ansible/roles/coredns/` 配下の変更が main にマージされると自動デプロイされる。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `coredns` | `coredns/coredns`（タグは `defaults/main.yml` 参照） | 53/udp、53/tcp | 内部レコードの応答と外部への転送 |

ホストの 53/udp・53/tcp を `coredns_bind_address` に公開する。Traefik のネットワーク（`traefik-public`）には接続せず、Traefik 経由での公開も行わない。

## 配置ファイル

| 配置先 | テンプレート | 内容 |
| --- | --- | --- |
| `/opt/coredns/docker-compose.yml` | `templates/docker-compose.yml.j2` | コンテナ定義 |
| `/opt/coredns/config/Corefile` | `templates/Corefile.j2` | CoreDNS 本体設定（コンテナ内 `/Corefile` に読み取り専用マウント） |
| `/opt/coredns/config/custom.hosts` | `templates/custom.hosts.j2` | 内部 DNS レコード（hosts 形式、コンテナ内 `/custom.hosts`） |

`/opt/coredns` と `/opt/coredns/config` は setup ロールで作成済みであることが前提。

## 主要変数

| 変数 | 用途・設計意図 |
| --- | --- |
| `coredns_upstream_dns` | hosts に該当が無い名前の転送先。可用性のため複数指定する |
| `coredns_cache_ttl` | `cache` プラグインの TTL（秒）。内部レコードを変更したときの反映遅延にもなるため短めにしている |
| `coredns_bind_address` | ホスト側の待ち受けアドレス。既定は全インタフェース。内部ネットワーク限定にする場合は特定 IP を指定する |
| `coredns_dns_records` | 返す A レコード。`defaults/main.yml` には書式のコメントのみを置き、実体は `vars/main.yml` で定義する |

Corefile は `hosts`（`fallthrough` 付き）→ `forward` の順に処理し、`cache`・`log`・`errors`・`reload`・`loadbalance` を有効にしている。

### DNS レコードの 3 層構造

内部 DNS レコードの追加・変更は 3 ファイルにまたがる。

| 層 | ファイル | 持つ情報 |
| --- | --- | --- |
| レコードの組み立て | `ansible/roles/coredns/vars/main.yml` | どの IP にどの FQDN 変数を紐づけるか |
| FQDN の実値 | `ansible/group_vars/local.yml` | `<サービス>_traefik_host`（CoreDNS と Traefik が共用） |
| IP アドレス | `ansible/roles/coredns/vars/vault.yml` | 暗号化された内部 IP |

FQDN を追加・変更するだけなら vault の復号は不要。

### Vault 変数

- `coredns_vault_ip_internal`

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make coredns` |
| 開発機 | `make deploy-coredns` |

Vault パスワード（`--ask-vault-pass`）が必要。sudo パスワードは不要。
`docker-compose.yml`・`Corefile`・`custom.hosts` のいずれかが変化すると、ハンドラで CoreDNS コンテナが再起動する。

## 運用上の注意

- **CoreDNS の停止はホストと全コンテナの名前解決障害に直結する**。`/etc/docker/daemon.json` の DNS 上流がこのコンテナを指しているため、停止中は内部名も外部名も引けなくなる。安易にコンテナを止めない、`restart: unless-stopped` を外さないこと
- レコードを増やすときは上表の 3 層すべてを更新する。どれか 1 層だけを変更すると未定義変数でテンプレート展開に失敗する
- 内部ゾーンに権威応答（`aa` フラグ）を返すことが、ACME への唯一の干渉点。`internal.kagiyama.net` は hosts プラグインが `aa` 付きで応答するため Traefik（lego）の権威 NS 自動検出を妨げるが、`_acme-challenge.*` は hosts に無く fallthrough して forward へ流れるため DNS-01 チャレンジ自体には干渉しない。対処は traefik ロールの `traefik_acme_resolvers` 明示指定で完結している。詳細は [docs/dns.md](../../../docs/dns.md)
- 干渉しているかどうかは `dig` の flags に `aa` が立つかで判別する。ゾーン単位ではなくレコード単位で確認すること
- `reload` プラグインにより Corefile の変更はコンテナ内でも自動で読み直されるが、Ansible 経由の変更ではハンドラでコンテナごと再起動して確実に反映する
- レコード変更の反映は `coredns_cache_ttl` の分だけ遅れる。確認時はキャッシュの期限切れを待つか、`dig @<CoreDNS のアドレス> <FQDN>` で直接引く
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、サーバへ適用する場合は必ず `make deploy-coredns` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/dns.md](../../../docs/dns.md) — DNS 構成と障害の経緯
- [setup ロール](../setup/README.md) — Docker デーモンの DNS 上流設定
- [traefik ロール](../traefik/README.md) — ACME と権威 NS の明示指定
