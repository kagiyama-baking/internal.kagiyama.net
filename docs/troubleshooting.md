# トラブルシューティング

症状を起点に、調査の入口と過去の障害から得た知見をまとめる。
個別サービスの詳細は各ロールの README（`ansible/roles/<ロール名>/README.md`）を参照。

## 症状別の調査手順

### HTTPS 証明書エラー（「この接続ではプライバシーが保護されません」）

1. 失敗の**理由**から見る: `docker logs traefik 2>&1 | grep -i acme`
2. 期限の実測: `echo | openssl s_client -connect <FQDN>:443 2>/dev/null | openssl x509 -noout -enddate`（更新契機は期限 30 日前）
3. 理由が DNS なら [docs/dns.md](dns.md) の調査コマンドへ。Traefik コンテナの上流確認: `docker exec traefik cat /etc/resolv.conf`（`# ExtServers:` 行）
4. Route 53 の権威 NS と `traefik_acme_resolvers`（traefik defaults）の一致を確認

過去事例: PR #112（コンテナが古い DNS 上流を保持し更新停止）。証明書設定側をいくら見ても原因に届かない。

### 内部ドメイン（*.internal.kagiyama.net）が引けない

1. どこから引けないかを切り分ける: LAN クライアント / ホスト / コンテナ内
2. コンテナ内なら上流を確認: `docker exec <コンテナ> cat /etc/resolv.conf`（`# ExtServers:` が CoreDNS を指しているか）
3. CoreDNS 自体の確認: `docker ps --filter name=coredns` / `dig @<サーバIP> internal.kagiyama.net`
4. `/etc/docker/daemon.json` が CoreDNS を指しているか（**外部 DNS 直指定は禁止**。[docs/dns.md](dns.md) の不変条件）

過去事例: PR #113（daemon.json に 8.8.8.8 を設定し内部解決が全滅）→ PR #115 で CoreDNS に統一。

### コンテナが unhealthy / 起動しない

1. `docker ps -a` で状態、`docker logs <コンテナ>` でエラーを確認
2. よくある原因（すべて過去に実際に踏んだもの）:
   - **healthcheck コマンドがイメージに存在しない**（distroless / Wolfi 系は curl/wget が無い）→ `docker exec <コンテナ> which curl` 等で事前確認。python3 内蔵なら urllib で代替
   - **`cap_drop: ALL` のコンテナは他ユーザー所有の 0600 ファイルを読めない**（root でも）→ 設定ファイルは 0644 で配置し、機密は環境変数で渡す
   - **healthcheck の `localhost` が IPv6（::1）に解決**され、IPv4 のみリッスンのアプリに繋がらない → 常に `127.0.0.1` を使う
   - **DATABASE_URL の未エンコード特殊文字**（`P1013: invalid port number` 等の間接的なエラーになる）→ パスワードは urlencode
   - **DB 列不足エラー**（`column ... does not exist`）は「migration 未実行」より「**後続 migration で drop された**」を疑い、migration の全履歴を見る（LiteLLM で実例。[litellm ロール README](../ansible/roles/litellm/README.md)）
3. Traefik は unhealthy なバックエンドをルーティングから除外する。外部から 404 でもコンテナは Up のことがある

### LLM API（talk 等）が 500 を返す

依存の連鎖: django-api → litellm-proxy → 外部 LLM プロバイダ。トレースは LangFuse に記録される。

1. `docker ps --filter name=litellm-proxy` — unhealthy なら上記「コンテナが unhealthy」へ
2. `docker logs litellm-proxy` でプロバイダ側エラーか設定エラーかを切り分け
3. LangFuse（`langfuse.internal.kagiyama.net`）でトレースを確認
4. モデル定義は **DB 管理**（Git 管理外）。Web UI（`litellm.internal.kagiyama.net`）で設定を確認
5. 音声合成のみ失敗する場合は外部 TTS ホストの疎通を確認（[app ロール README](../ansible/roles/app/README.md)）

### バックアップ失敗通知（Slack アラート）

1. `journalctl -t autorestic-backup` で失敗箇所を特定（pg_dump / autorestic backup / forget のどこか）
2. `make backup-status` でリポジトリ整合性とスナップショット一覧を確認
3. S3 接続・認証情報（vault）・対象コンテナ（immich-database / app-database）の稼働を確認
4. アラート「バックアップが一定時間実施されていない」（閾値は observability の `defaults/main.yml` 参照）は cron 停止・サーバ再起動後の未実行も疑う（`crontab -l`）

手順の詳細は [docs/backup-restore.md](backup-restore.md)。

## 予防原則（変更を入れる前に）

過去の障害・手戻りから定めた原則。詳細な経緯は各ロール README の「運用上の注意」にある。

- **開発機で `ansible-playbook` / `make <ロール名>` を直接実行しない**。インベントリが `localhost` のため**開発機自身に適用される**。サーバへの適用は必ず `make deploy-*` を使う
- **新しいイメージタグは push 前に `docker manifest inspect <image>` で実在確認**（pull 不要・10 秒で防げる）
- **イメージ選定時は healthcheck に使えるツール（curl 等）の有無を確認**。distroless 系は本番で使わない
- **コンテナがデータを持つディレクトリを Ansible で作らない**（所有権変更で再デプロイ時に EPERM）。Compose の初回起動に任せる。`become` が必要な操作は setup ロールに寄せる
- **Grafana のデータソース UID・アラートフォルダ名は一度決めたら変更しない**（変更は破壊的。[observability ロール README](../ansible/roles/observability/README.md)）
- **Grafana の UI 上で行った編集はデプロイで消える**（ダッシュボードは Git の JSON が正）
- **PromQL 内の比較演算と Grafana の Threshold を二重に使わない**（常時発火になる）
- **適用範囲を広げる変更は前提を再検証する**。1 コンテナで正しい設定が N コンテナで正しいとは限らない（PR #113 の教訓）
- **緊急時は影響を局所化した修正で先に止血し、恒久対策は別 PR に分ける**（PR #112 → #113 のパターン）
- **`make check`（ドライラン）は sudo パスワードのみで vault を復号しないため、Vault 使用ロールでは失敗する可能性がある**（既知の制約）

## 関連ドキュメント

- [docs/dns.md](dns.md) — DNS 設計・不変条件・調査コマンド
- [docs/backup-restore.md](backup-restore.md) — バックアップとリストア
- [README.md](../README.md) — 全体像・デプロイ・CI/CD
