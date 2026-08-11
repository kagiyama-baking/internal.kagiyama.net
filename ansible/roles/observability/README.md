# observability ロール

Grafana・Prometheus・Loki を中心とした監視・ログ基盤をデプロイするロール。

## 概要

メトリクス収集（Prometheus + Node Exporter + cAdvisor）、ログ収集（Loki + Promtail）、可視化とアラート（Grafana）を 1 つの Compose プロジェクトとして構築する。
Grafana の公開 FQDN は `grafana_traefik_host`（`ansible/group_vars/local.yml`）。site.yml のタグは `observability`。
CD（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`）の対象であり、`ansible/roles/observability/` の変更が main にマージされると自動デプロイされる。

## コンテナ構成

| コンテナ名 | イメージ | 内部ポート | 役割 |
| --- | --- | --- | --- |
| `grafana` | `grafana/grafana` | 3000 | ダッシュボードと Unified Alerting。Traefik のルーティング先 |
| `prometheus` | `prom/prometheus` | 9090 | メトリクスの収集と保存 |
| `loki` | `grafana/loki` | 3100 | ログの保存と検索 |
| `loki-init` | `grafana/loki` | — | 起動前に `loki-data` の所有権を Loki の UID へ変更する使い捨てコンテナ |
| `node-exporter` | `prom/node-exporter` | 9100 | ホストの CPU・メモリ・ディスクを収集 |
| `cadvisor` | `gcr.io/cadvisor/cadvisor` | 8080 | コンテナ単位のリソースを収集 |
| `promtail` | `grafana/promtail` | 9080 | Docker ログ・syslog・auth.log を Loki へ転送 |

イメージのタグは `defaults/main.yml` を参照。
Grafana のみ `traefik_network_name` と `observability-internal` の両方に属し、残りは `observability-internal` に閉じる。
Prometheus のスクレイプ対象は自身・`node-exporter`・`cadvisor` の 3 つ（`templates/prometheus.yml.j2`）。Promtail は Docker のサービスディスカバリで全コンテナのログを自動収集し、加えてホストの `/var/log/syslog` と `/var/log/auth.log` を読む。

## 配置ファイル

| 配置先 | ソース | 権限 | 内容 |
| --- | --- | --- | --- |
| `/opt/observability/docker-compose.yml` | `templates/docker-compose.yml.j2` | 0600 | 7 コンテナの定義 |
| `/opt/observability/grafana.env` | `templates/grafana.env.j2` | 0600 | 管理者パスワード、ルート URL、Unified Alerting の有効化 |
| `/opt/observability/prometheus.yml` | `templates/prometheus.yml.j2` | 0644 | スクレイプ設定 |
| `/opt/observability/loki.yml` | `templates/loki.yml.j2` | 0644 | ストレージ・保持期間・コンパクタ設定 |
| `/opt/observability/promtail.yml` | `templates/promtail.yml.j2` | 0644 | ログ収集ジョブ |
| `/opt/observability/grafana/datasources.yml` | `templates/grafana/datasources.yml.j2` | 0644 | Prometheus / Loki データソース |
| `/opt/observability/grafana/dashboards.yml` | `templates/grafana/dashboards.yml.j2` | 0644 | ダッシュボードプロバイダ |
| `/opt/observability/grafana/alerting/rules.yml` | `templates/grafana/alerting/rules.yml.j2` | 0644 | アラートルール |
| `/opt/observability/grafana/alerting/contactpoints.yml` | `templates/grafana/alerting/contactpoints.yml.j2` | 0644 | Slack 通知先 |
| `/opt/observability/grafana/alerting/policies.yml` | `templates/grafana/alerting/policies.yml.j2` | 0644 | 通知ポリシー |
| `/opt/observability/dashboards/` | `files/dashboards/`（`synchronize`、`delete: true`） | — | ダッシュボード JSON |

## アラート構成

`templates/grafana/alerting/rules.yml.j2` が `Alerting` フォルダに以下を生成する。

| ルール | データソース | 判定 | severity |
| --- | --- | --- | --- |
| コンテナダウン（`observability_alert_containers` の要素ごとに 1 本、現在 11 本） | Prometheus | `absent_over_time(container_last_seen{name="..."}[10m])` が 1 件でも返れば発火 | critical |
| バックアップ失敗 | Loki | syslog に autorestic の `Backup failed` が出現したら即発火 | critical |
| バックアップ未実行 | Loki | `observability_alert_backup_missing_hours` 時間内に成功ログが無ければ発火 | warning |
| ディスク使用率が 90% 超過 | Prometheus | 仮想ファイルシステムを除く最大使用率が 90% 超で 5 分継続 | warning |

通知先はコンタクトポイント `slack` の 1 つのみで、通知ポリシーは全アラートをそこへ送る（`group_wait` 30 秒 / `group_interval` 5 分 / `repeat_interval` 4 時間）。

## 主要変数

| 変数 | 設計・運用上の意図 |
| --- | --- |
| `observability_alert_containers` | **コンテナダウン検知の対象リスト**。ここに無いコンテナは落ちても通知されない（後述） |
| `observability_alert_backup_missing_hours` | 未実行検知の時間窓。日次 3:00 実行に対しバッファを持たせた値 |
| `observability_prometheus_retention` / `observability_loki_retention` | メトリクスとログの保持期間。ディスク消費に直結する |
| `observability_grafana_bind_address` | ホストポートの bind 先。Traefik 経由のみに限定する意図でループバックを既定とする |

### Vault 変数

`vars/vault.yml`（ansible-vault で暗号化）に以下を保持する。

- `observability_vault_grafana_admin_password`
- `observability_vault_slack_webhook_url`

## デプロイ

| 実行場所 | コマンド |
| --- | --- |
| サーバ上 | `make observability` |
| 開発機 | `make deploy-observability` |

Vault パスワードが必要（`--ask-vault-pass`）。sudo パスワードは不要。
上表の設定ファイルとダッシュボード JSON はいずれもハンドラ `Observability を再起動` を notify するため、1 ファイルでも変化すると Compose プロジェクト全体が `state: restarted` で再起動する。

## 運用上の注意

- **新しいサービスを追加したら `observability_alert_containers` に必ず追加する**。ここへの追加を忘れると、そのコンテナが停止しても誰も気付けない。現在の対象は immich 系 4 つ、`django-api`、`frontend`、`traefik`、`portainer`、`coredns`、`langfuse-web`、`langfuse-worker` の 11 件
- 上記の裏返しとして、**稼働中でも監視対象外のコンテナが多数ある**。`celery-worker` / `celery-beat` / `app-database` / `redis` / `litellm-proxy` / `litellm-database` / `langfuse-database` / `langfuse-clickhouse` / `langfuse-redis`、および observability スタック自身（`grafana` / `prometheus` / `loki` / `promtail` / `cadvisor` / `node-exporter`）が該当する。これらが意図的な除外なのか単に未追加なのかを示す記録は残っていない。特に Grafana 自身が落ちた場合はアラートの発報経路ごと失われる点に注意する
- **コンテナダウン検知に `absent_over_time` を使うのは必然**。コンテナが停止すると cAdvisor は `container_last_seen` の報告自体を止めるため、`time() - container_last_seen` のような閾値比較は空の結果を返し検知できない。メトリクスの「不在」で判定する必要がある
- **PromQL 内で比較演算（`> 90` 等）をしない**。比較すると結果が元の値ではなく `1` になり、Grafana の Reduce + Threshold と組み合わさって「値が存在すれば常に発火」になる。PromQL は素の値を返し、閾値判定は Grafana の Threshold 側で行う
- **データソースの UID 変更は破壊的**。既存の Grafana DB に旧 UID が残った状態で `uid` を変更・追加すると Grafana が起動しなくなる。`datasources.yml.j2` の `deleteDatasources` で旧データソースを削除してから再作成する構成を崩さないこと
- **アラートルールの `folder` 名は変更しない**。`folder: ""` は起動エラーになるうえ、フォルダ名を変えると旧フォルダにルールが残って重複する（自動クリーンアップされない）。重複が生じた場合の解消は Grafana ボリュームのリセットになる
- **ダッシュボードは `files/dashboards/` が正**。`synchronize` の `delete: true` で同期するため、**Grafana の UI 上で編集した内容は次回デプロイで消える**。変更はリポジトリ側の JSON に対して行う
- **Grafana コンテナは UID 472 で実行される**。プロビジョニング配下のファイルは 0644 でなければ読めない。機密を含むからと 0600 にすると Grafana が設定を読めず起動に失敗する。秘密値は `grafana.env`（0600、`env_file` で渡すのでコンテナが直接読む必要がない）に寄せている
- `loki-init` は起動時に一度だけ動く chown 用コンテナで、正常時も `Exited (0)` のまま残る。停止しているように見えても異常ではない
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ（`localhost` への local 接続）。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、必ず `make deploy-observability` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/troubleshooting.md](../../../docs/troubleshooting.md) — 障害調査の起点
- [backup ロール](../backup/README.md) — アラートが監視している autorestic バックアップ
- [traefik ロール](../traefik/README.md) — HTTPS 終端と証明書
