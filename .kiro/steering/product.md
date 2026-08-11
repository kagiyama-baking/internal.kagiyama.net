# Product Overview

鍵山製パン家の自宅サーバ（UTM 上の Ubuntu Server）を、Ansible で再現可能・冪等にプロビジョニングし、複数の Docker サービスを Traefik 経由で公開・運用するためのオートメーション基盤。

利用者は単一の運用者（オーナー個人）であり、家族・自分の用途（写真管理、観測、LLM 実験、社内アプリ）を支える「ホームラボ」を、属人化させず Git で管理することを目的とする。

## Core Capabilities

- **構成管理 (Configuration Management)**: ホスト OS（ロケール、タイムゾーン、Docker、ファイアウォール等）を Ansible でセットアップし、状態を Git に集約する
- **サービスオーケストレーション (Service Orchestration)**: 各サービスは Docker Compose v2 で起動し、Traefik (Let's Encrypt + Route 53 DNS-01) が `*.internal.kagiyama.net` 配下へ HTTPS 公開する
- **バックアップ自動化 (Backup Automation)**: autorestic / restic で重要ボリュームを AWS S3 にスケジュールバックアップ
- **クラウド IaC (Cloud IaC)**: LangFuse 用の S3 バケット（event / media / export）と IAM ユーザーを OpenTofu で宣言的に管理（バックアップ用 S3 / IAM は tofu 管理外で、手動作成し接続情報を Vault で保持する）
- **観測性 (Observability)**: Prometheus / Loki / Promtail / Grafana スタックを同居させ、自宅ホストおよびコンテナのメトリクス・ログを一元集約

## Target Use Cases

- 自宅 Ubuntu サーバへのサービス新規追加・更新を、ロール追加 + タグ指定の最小差分で行う
- PR マージ起点での自動デプロイ（GitHub Actions → Tailscale → SSH → ansible-playbook）
- インフラ全体の破壊・再構築（disaster recovery）を、ドキュメント化された手順と Git の状態から復元

## Value Proposition

- **タグ単位の部分デプロイ**: `site.yml` のロールが各 1 プレイ・1 タグで構成され、`make deploy-<role>` または GitHub Actions のパス差分検出により、変更されたロールだけを安全に再適用できる
- **二層 Makefile UX**: 開発機からは `make deploy-*`（SSH 経由）、サーバ上では `make <role>`（直接実行）と同じ語彙を共有し、運用者が手順を覚えやすい
- **Vault による秘密分離**: 各ロールの `vars/vault.yml` に秘密値を閉じ込め、コミット可能な平文と暗号化された値を明確に分離

---
_Focus on patterns and purpose, not exhaustive feature lists_
