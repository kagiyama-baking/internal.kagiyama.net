# observability ロール

Grafana・Prometheus・Loki を中心とした監視・ログ基盤をデプロイするロール。

## 概要

メトリクス収集（Prometheus + Node Exporter + cAdvisor）、ログ収集（Loki + Alloy）、可視化とアラート（Grafana）を 1 つの Compose プロジェクトとして構築する。
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
| `alloy` | `grafana/alloy` | 12345（コンテナ内のみ） | Docker ログ・syslog・auth.log を Loki へ転送（Promtail の後継） |

イメージのタグは `defaults/main.yml` を参照。
Grafana のみ `traefik_network_name` と `observability-internal` の両方に属し、残りは `observability-internal` に閉じる。
Prometheus のスクレイプ対象は自身・`node-exporter`・`cadvisor` の 3 つ（`templates/prometheus.yml.j2`）。Alloy は Docker のサービスディスカバリで全コンテナのログを自動収集し、加えてホストの `/var/log/syslog` と `/var/log/auth.log` を読む（`templates/config.alloy.j2`）。

## 配置ファイル

| 配置先 | ソース | 権限 | 内容 |
| --- | --- | --- | --- |
| `/opt/observability/docker-compose.yml` | `templates/docker-compose.yml.j2` | 0600 | 7 コンテナの定義 |
| `/opt/observability/grafana.env` | `templates/grafana.env.j2` | 0600 | 管理者パスワード、Slack の Webhook URL、ルート URL、Unified Alerting の有効化 |
| `/opt/observability/prometheus.yml` | `templates/prometheus.yml.j2` | 0644 | スクレイプ設定 |
| `/opt/observability/loki.yml` | `templates/loki.yml.j2` | 0644 | ストレージ・保持期間・コンパクタ設定 |
| `/opt/observability/config.alloy` | `templates/config.alloy.j2` | 0644 | ログ収集の設定（Alloy） |
| `/opt/observability/grafana/datasources.yml` | `templates/grafana/datasources.yml.j2` | 0644 | Prometheus / Loki データソース |
| `/opt/observability/grafana/dashboards.yml` | `templates/grafana/dashboards.yml.j2` | 0644 | ダッシュボードプロバイダ |
| `/opt/observability/grafana/alerting/rules.yml` | `templates/grafana/alerting/rules.yml.j2` | 0644 | アラートルール |
| `/opt/observability/grafana/alerting/contactpoints.yml` | `templates/grafana/alerting/contactpoints.yml.j2` | 0644 | Slack 通知先（URL は `grafana.env` の環境変数を参照） |
| `/opt/observability/grafana/alerting/policies.yml` | `templates/grafana/alerting/policies.yml.j2` | 0644 | 通知ポリシー |
| `/opt/observability/dashboards/` | `files/dashboards/`（`synchronize`、`delete: true`） | — | ダッシュボード JSON |

## アラート構成

`templates/grafana/alerting/rules.yml.j2` が `Alerting` フォルダに以下を生成する。

| ルール | データソース | 判定 | severity |
| --- | --- | --- | --- |
| コンテナダウン（`observability_alert_containers` の要素ごとに 1 本） | Prometheus | `absent_over_time(container_last_seen{name="..."}[10m])` に直近 2 分の cAdvisor の取得状況を掛けた値が 0 より大きければ発火 | critical |
| cAdvisor 停止 | Prometheus | 直近 10 分の `up{job="cadvisor"}` の平均が 0.5 未満、またはデータがなければ発火 | critical |
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
「配置ファイル」の表の設定ファイル（`docker-compose.yml` を除く）とダッシュボード JSON はいずれもハンドラ `Observability を再起動` を notify するため、1 ファイルでも変化すると Compose プロジェクト全体が `state: restarted` で再起動する。
`docker-compose.yml` の差分（イメージタグの更新など）はハンドラを発火させず、タスク側の `state: present` が変わったコンテナだけ再作成して反映する。

## 運用上の注意

- **新しいサービスを追加したら `observability_alert_containers` に必ず追加する**。ここへの追加を忘れると、そのコンテナが停止しても誰も気付けない。現在の対象は immich 系 4 つ、`django-api`、`frontend`、`traefik`、`portainer`、`coredns`、`langfuse-web`、`langfuse-worker` の 11 件
- 上記の裏返しとして、**稼働中でも監視対象外のコンテナが多数ある**。`celery-worker` / `celery-beat` / `app-database` / `redis` / `litellm-proxy` / `litellm-database` / `langfuse-database` / `langfuse-clickhouse` / `langfuse-redis`、および observability スタック自身（`grafana` / `prometheus` / `loki` / `alloy` / `node-exporter`）が該当する。これらが意図的な除外なのか単に未追加なのかを示す記録は残っていない。特に Grafana 自身が落ちた場合はアラートの発報経路ごと失われる点に注意する
- **コンテナダウン検知に `absent_over_time` を使うのは必然**。コンテナが停止すると cAdvisor は `container_last_seen` の報告自体を止めるため、`time() - container_last_seen` のような閾値比較は空の結果を返し検知できない。メトリクスの「不在」で判定する必要がある
- **cAdvisor が止まっているあいだは、コンテナの停止を検知できない**。不在の判定はコンテナの停止と cAdvisor の停止を区別できないので、cAdvisor の取得状況（`up`）を掛けて後者では発火させず、「cAdvisor 停止」の 1 件で通知する。cAdvisor の停止中に止まったコンテナは、最後に観測されてから 10 分経ち、かつ cAdvisor の復帰から 2 分経った時点で通知される
- **「cAdvisor 停止」は 10 分間の平均で判定する**。短い再起動では発火せず、OOM を繰り返す場合も短い復帰では解消しない。これで通知が発火と解消を往復しにくくなる
- **cAdvisor の起動オプションを外さない**。`--disable_metrics` から `disk` を外すと、containerd snapshotter の環境ではディスク使用量の収集が全コンテナの rootfs を走査し続け、走査のキャッシュでメモリ上限に達して OOM Kill を繰り返し、メトリクスを取得できなくなる。`container_fs_usage_bytes` などの容量系は出なくなるが、ダッシュボードとアラートでは使っていない。`--docker_only=true` は、報告を Docker コンテナとホスト全体に絞って系列数を抑える
- **`--disable_metrics` は既定のリストに `disk` を足した形で指定する**。この値は既定の無効リストを置き換えるので、`disk` だけを指定するとプロセス系のメトリクスまで有効になる。すると cAdvisor の読み取りが AppArmor に拒否され続け（`operation="ptrace" comm="cadvisor"`）、カーネルログと cAdvisor のログ（`Cannot read smaps`）が埋まる。cAdvisor を更新するときは `cadvisor --help` で既定のリストを確かめ、差があれば `command` を既定のリストと `disk` に合わせる
- **PromQL 内で比較演算（`> 90` 等）をしない**。比較すると結果が元の値ではなく `1` になり、Grafana の Reduce + Threshold と組み合わさって「値が存在すれば常に発火」になる。PromQL は素の値を返し、閾値判定は Grafana の Threshold 側で行う
- **データソースの UID 変更は破壊的**。既存の Grafana DB に旧 UID が残った状態で `uid` を変更・追加すると Grafana が起動しなくなる。`datasources.yml.j2` の `deleteDatasources` で旧データソースを削除してから再作成する構成を崩さないこと
- **アラートルールの `folder` 名は変更しない**。`folder: ""` は起動エラーになるうえ、フォルダ名を変えると旧フォルダにルールが残って重複する（自動クリーンアップされない）。重複が生じた場合の解消は Grafana ボリュームのリセットになる
- **ダッシュボードは `files/dashboards/` が正**。`synchronize` の `delete: true` で同期するため、**Grafana の UI 上で編集した内容は次回デプロイで消える**。変更はリポジトリ側の JSON に対して行う
- **Grafana コンテナは UID 472 で実行される**。プロビジョニング配下のファイルは 0644 でなければ読めない。機密を含むからと 0600 にすると Grafana が設定を読めず起動に失敗する。秘密値は `grafana.env`（0600、`env_file` で渡すのでコンテナが直接読む必要がない）に寄せている。Slack の Webhook URL も同様で、`contactpoints.yml` には `${SLACK_WEBHOOK_URL}` とだけ書き、Grafana が起動時に `grafana.env` の値で展開する。**この変数が無いと provisioning が失敗して Grafana が起動しない**（`recipient must be specified when using the Slack chat API`）ので、`grafana.env` から消さないこと。新しい値がコンテナに届くのは起動タスクの `state: present` が env の差分で Grafana を作り直すときなので、ファイル配置の後でデプロイが失敗したら放置せず再デプロイを完了させる（ファイルだけ新しくコンテナが古いままだと、次の再起動で変数が無く起動できない）
- **コンタクトポイントの `settings` とアラートルールのラベルでは、Grafana が `$VAR` を環境変数として展開する**。アラートルールの注釈は展開されず生の値で取り込まれるので、`{{ $labels.x }}` や `{{ $value }}` はそのまま書く（`$$` に変えると文字どおり残って壊れる）。また Ansible の `trim_blocks` は `{% endraw %}` 直後の改行を消す（`{% raw %}` の後ろの改行は残す）ので、`{% raw %}` は直前の行の末尾に、`{% endraw %}` は単独の行に置く。`{% endraw %}` を行末に置くと次の行が連結され、`text` や `labels` のキーが消える
- **ログ収集は Alloy（Promtail の後継）**。Loki に入るラベルは Promtail のときと同じ `job` / `service_name` / `container_name` / `filename` で、`templates/config.alloy.j2` はこれを変えない前提（アラートが `{job="syslog"}` を使う）。Alloy は root + `cap_drop: ALL` + `DAC_READ_SEARCH` で動かし、保存先（読み出し位置）は `alloy_data` ボリュームの `/data`。イメージの `/var/lib/alloy/data` は alloy ユーザー所有で、`DAC_OVERRIDE` を落とした root では書けないので使わない。`docker.sock` の `:ro` は Docker API の書き込みを防がない（Promtail のときと同じ既知の露出）
- **`alloy_data` を消すと読み出し位置が失われる**。syslog / auth.log は `tail_from_end` が効いて末尾から読む（停止中の分が欠けるだけ。ファイル全体を今の時刻で読み直すと古い `Backup failed` 行でアラートが誤発火するので、その方が安全）。Docker ログは各コンテナのログを先頭から読み直す（Loki が 7 日より古い行を拒否するので重複は最大 7 日分で、保持期間 `observability_loki_retention` を過ぎると消える。アラートは syslog しか見ないので影響なし）
- **Docker ログの読み出し位置は「コンテナ ID ＋ 対象のラベル一式」で保存される**。`templates/config.alloy.j2` の `discovery.relabel "docker"` の最後の `labelkeep` で、`loki.source.docker` が使うコンテナ ID（`__meta_docker_container_id`）と Loki に送る 3 つのラベルだけを残している。IP（`__address__`）やネットワークのラベルを残すと、再起動で IP が変わったコンテナが位置の無い新しい対象になり、ログを先頭から読み直す（7 日より古い行は Loki が拒否して Alloy にエラー行が出る。新しい行の重複は Loki が問い合わせのときにまとめるので見えない）。残すラベルを変えると鍵が変わり、適用時に全コンテナのログを一度だけ読み直す。`labelkeep` は名前を作る規則より後に置く（前に置くと、名前の元の `__meta_docker_container_name` が先に消える）
- **起動タスクは `remove_orphans: true`**。compose から消したサービスのコンテナを孤児として残さないため（Promtail → Alloy の置き換えで必要になった）。このプロジェクト名で compose に無いコンテナを手で作ると消される
- `loki-init` は起動時に一度だけ動く chown 用コンテナで、正常時も `Exited (0)` のまま残る。停止しているように見えても異常ではない
- 適用先はインベントリ `ansible/inventories/local/hosts` の `local` グループ（`localhost` への local 接続）。開発機で `ansible-playbook` を直接叩くと**開発機自身**に適用されるため、必ず `make deploy-observability` を使う

## 関連ドキュメント

- [ansible/README.md](../../README.md) — ロール構成と Vault 運用
- [README.md](../../../README.md) — システム全体構成とデプロイ手順
- [docs/troubleshooting.md](../../../docs/troubleshooting.md) — 障害調査の起点
- [backup ロール](../backup/README.md) — アラートが監視している autorestic バックアップ
- [traefik ロール](../traefik/README.md) — HTTPS 終端と証明書
