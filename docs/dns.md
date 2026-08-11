# DNS 設計

内部ドメイン（`*.internal.kagiyama.net`）の解決と、Let's Encrypt 証明書更新（DNS-01 チャレンジ）の両立をどう実現しているかをまとめる。
2026-08 の DNS 障害対応（PR #112 / #113 / #115）で得た知見の恒久化先。

## 全体像

| 利用者 | DNS の参照先 | 備考 |
|---|---|---|
| LAN 内のクライアント | CoreDNS（サーバの `:53`） | ルータ/端末の DNS 設定で向ける |
| 各コンテナ | Docker 埋め込み DNS `127.0.0.11` | 上流 = `/etc/docker/daemon.json` の `dns`（= CoreDNS） |
| ホスト自身 | systemd-resolved | `/etc/resolv.conf` → `/run/systemd/resolve/resolv.conf`（DHCP 等の上流） |

CoreDNS は hosts プラグインで内部レコードに応答し、それ以外は forward で公開 DNS へ転送する（Corefile は `hosts` + `fallthrough` + `forward`。上流・キャッシュ TTL は `ansible/roles/coredns/defaults/main.yml` 参照）。

## 不変条件（変更してはならない設定）

1. **`/etc/docker/daemon.json` の `dns` は CoreDNS（ホスト自身の IP）のみを指す**。
   8.8.8.8 等の外部 DNS を直接指定してはならない。`*.internal.kagiyama.net` はパブリック DNS に存在しない内部専用レコードのため、外部 DNS を指定すると django-api / celery / litellm-proxy など内部 FQDN を参照するコンテナの名前解決が全滅する（PR #113 で実際に発生させた障害）。
2. **systemd-resolved のスタブリスナーは無効（`DNSStubListener=no`）**。CoreDNS がホストのポート 53 を使うため（setup ロールが設定）。
3. **`traefik_acme_resolvers` には Route 53 の権威ネームサーバを明示指定する**（理由は後述）。Route 53 側の NS 変更時は必ず追随する。

## なぜ daemon.json で上流を固定するのか

- コンテナ内の `nameserver` は常に `127.0.0.11`（Docker 埋め込み DNS）だが、その**上流**はコンテナ**起動時点**のホスト `/etc/resolv.conf` のスナップショットで、コンテナが Up の間ずっと保持される
- ホスト側の resolv.conf は Tailscale MagicDNS 等により変動する。応答しなくなった上流を掴んだままのコンテナは名前解決が恒久的に失敗する（PR #112: Traefik が 5 週間前の MagicDNS の値を握り続け、証明書更新が停止していた）
- `daemon.json` の `dns` で上流をデーモンレベルで固定し、全コンテナをホスト設定の変動から切り離す（PR #113 / #115）
- `daemon.json` の変更は Docker デーモン再起動（= 全コンテナ再起動）で全コンテナに反映される。コンテナごとの再デプロイは不要
- 症状の見え方: `lookup <host> on 127.0.0.11:53: server misbehaving`。`127.0.0.11` が原因に見えるが、**壊れているのは上流**

## ACME（Let's Encrypt）との関係

- CoreDNS は内部ゾーンに**権威応答（`aa` フラグ）**を返す。これが Traefik（lego）の権威 NS 自動検出を妨害するため、`traefik_acme_resolvers`（`ansible/roles/traefik/defaults/main.yml`）に Route 53 の権威 NS を明示指定している
- 一方 `_acme-challenge.*` は hosts に無く fallthrough → forward で外部へ流れる（`aa` 無しの応答）ため、チャレンジ用 TXT レコードの検証には干渉しない
- したがって「CoreDNS を上流にすると証明書更新が壊れる」は**誤り**（PR #112 の原因は MagicDNS であって CoreDNS ではない）
- 干渉の有無は `dig` の flags に `aa` が立つかで、ゾーン単位ではなく**レコード単位**で判別する

## 調査コマンド

| 確認したいこと | コマンド |
|---|---|
| コンテナが実際に使っている上流 | `docker exec <コンテナ> cat /etc/resolv.conf` の `# ExtServers:` 行 |
| 内部レコードがコンテナから引けるか | `docker exec <コンテナ> getent hosts internal.kagiyama.net` |
| CoreDNS の内部レコード応答（`aa` あり） | `dig @<サーバIP> internal.kagiyama.net` |
| チャレンジが forward されるか（`aa` 無し） | `dig @<サーバIP> _acme-challenge.internal.kagiyama.net` |
| 証明書更新失敗の理由 | `docker logs traefik 2>&1 \| grep -i acme` |
| 証明書期限の実測 | `echo \| openssl s_client -connect <FQDN>:443 2>/dev/null \| openssl x509 -noout -enddate` |
| Route 53 の現在の権威 NS | `dig NS <ホストゾーン名> +short`（`traefik_acme_resolvers` と一致すること） |

## 障害履歴（要約）

| PR | 内容 |
|---|---|
| #112 | Traefik が古い MagicDNS 上流を保持し証明書更新が停止 → Traefik 個別に `dns:` 指定で止血 |
| #113 | `daemon.json` で全コンテナの上流を恒久固定。ただし上流を 8.8.8.8 にしたため内部ドメイン解決が破壊 |
| #115 | 上流を CoreDNS に統一し、内部レコードと外部 forward の双方を満たして解決 |

教訓: 1 コンテナで正しかった設定（Traefik は内部名不要）が全コンテナで正しいとは限らない。適用範囲を広げるときは前提を再検証する。

## 関連ドキュメント

- [setup ロール README](../ansible/roles/setup/README.md) — daemon.json / systemd-resolved の設定主体
- [coredns ロール README](../ansible/roles/coredns/README.md) — 内部レコードの追加方法
- [traefik ロール README](../ansible/roles/traefik/README.md) — ACME 設定と権威 NS
- [docs/troubleshooting.md](troubleshooting.md) — 症状別の調査手順
