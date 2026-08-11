---
name: doc-sync
description: Sync repository documentation after infrastructure changes. Use after adding/modifying/removing Ansible roles, variables, containers, Makefile targets, CI workflows, or tofu resources, after incident response, and before creating any PR to verify documentation consistency.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Documentation Sync

コード変更とドキュメントの乖離をゼロに保つためのスキル。変更内容から更新すべきドキュメントを特定し、コードの実態と突き合わせて更新し、整合性チェックで検証する。

## Core Mission

- 変更種別 → 更新対象マトリクスに基づき、更新が必要なドキュメントを漏れなく特定する
- 「1 つの事実は 1 ドキュメントにのみ書く」担当境界を守り、重複を作らない
- 更新後に `scripts/check_docs.py` で機械検証する

## ドキュメントの担当境界（どこに何を書くか）

| 情報 | 唯一の記載場所 |
| --- | --- |
| サービス一覧・FQDN・アーキテクチャ図・Make コマンド表・CI/CD 概要 | ルート `README.md` |
| ロール一覧・ディレクトリ規約・Vault 運用・ロール追加手順・共有変数 | `ansible/README.md` |
| ロール固有のコンテナ構成・変数・vault キー・運用上の注意・IAM ポリシー | `ansible/roles/<role>/README.md` |
| 初期構築 / バックアップ・リストア / DNS 設計 / 障害対応 | `docs/` の 4 ファイル |
| OpenTofu の管理対象・state 運用 | `tofu/README.md` |
| AI 向けプロジェクト規則 | `CLAUDE.md` / `.claude/CLAUDE.md` / `.kiro/steering/` |

**ドキュメントに書かないもの**: イメージタグ・バージョン番号・IP アドレス・秘密値・バケット名。「`defaults/main.yml` 参照」「vault 参照」と書く（陳腐化防止の最重要原則。タグ更新のたびに README を直す運用にしない）。

## Execution Steps

1. **変更の特定**: `git diff --name-only main...HEAD`（または指示された変更内容）で変更ファイルを列挙する
2. **更新対象の決定**: 下記マトリクスに当てはめ、更新対象ドキュメントの一覧を提示する
3. **突き合わせ更新**: 各対象について、コードの実態（defaults / tasks / handlers / templates / site.yml / Makefile / deploy.yml）を Read してからドキュメントを更新する。記憶や推測で書かない
4. **機械検証**: `uv run python scripts/check_docs.py` を実行し exit 0 を確認する（CI の Docs Check と同一の検査）
5. **報告**: 更新したファイル一覧と、「更新不要と判断した候補とその理由」を報告する

## 変更種別 → 更新対象マトリクス

| 変更 | 更新対象 |
| --- | --- |
| ロールの追加 / 削除 | **5 点セット**: ① `ansible/site.yml` ② ルート `Makefile`（`<role>` / `deploy-<role>` + `.PHONY`）③ `.github/workflows/deploy.yml` のロール列挙 5 箇所 ④ `roles/<role>/README.md` ⑤ `ansible/README.md` のロール一覧表。さらにルート README（サービス表・コマンド表・アーキテクチャ図）を更新し、`observability_alert_containers` への追加要否と backup の対象 / 対象外表への記載を明示的に判断する |
| コンテナの追加 / 削除（既存ロール内） | ロール README のコンテナ表、ルート README のアーキテクチャ図、`observability_alert_containers` の要否 |
| defaults 変数の追加 / 変更 | ロール README の主要変数節（設計判断がある変数のみ。機械的な値は書かない） |
| vault キーの追加 / 削除 | ロール README の「Vault 変数」一覧 |
| イメージタグの更新のみ | **ドキュメント更新不要**（タグを README に書かない原則のため）。メジャー更新時はロール README の手順（immich が代表例）に従い、作業記録は `tasks/` に残す |
| Make ターゲットの追加 / 変更 | ルート README のコマンド表。`tofu/Makefile` の場合はヘッダコメントと `tofu/README.md` |
| FQDN・DNS レコードの変更 | `ansible/group_vars/local.yml`、ルート README（表・図）、coredns ロール README、必要なら `docs/dns.md`。FQDN 直書き 3 箇所（`ansible/README.md` の「既知の課題」参照）の追随も確認する |
| バックアップ対象の変更 | backup ロール README（対象 / 対象外表）、`docs/backup-restore.md`、observability のアラート整合 |
| CI ワークフローの変更 | ルート README の CI/CD 節。`deploy.yml` のロール列挙構造を変えた場合は `scripts/check_docs.py`（C3）の追随も確認する |
| tofu リソースの変更 | `tofu/README.md`、（LangFuse 関連なら）langfuse ロール README |
| 障害対応の完了後 | `tasks/lessons.md` に一次記録し、恒久化すべき知見は `docs/troubleshooting.md` または該当ロール README の「運用上の注意」へ昇格する |
| 規約・構造の変更 | `ansible/README.md`、`.kiro/steering/`、`CLAUDE.md` / `.claude/CLAUDE.md` |

## Critical Constraints

- ドキュメントは**すべて日本語**で書く（既存の簡潔な常体に合わせる）
- 同じ事実を 2 箇所に書かない。担当境界の表に従い、他の場所からは相対リンクで参照する
- イメージタグ・バージョン・IP アドレス・秘密値・バケット名を書かない
- `ansible/**` の md 以外のファイル変更を提案する場合は、**main マージで CD（自動デプロイ）が発火する**ことを必ず明示する
- 本番サーバへの変更は行わない（このスキルの範囲はドキュメントと整合性チェックのみ）

## Output Description

チャットで以下を報告する: (1) 更新したドキュメントの一覧と各変更の要約、(2) 更新不要と判断した候補とその理由、(3) `scripts/check_docs.py` の実行結果。
