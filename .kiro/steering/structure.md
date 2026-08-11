# Project Structure

## Organization Philosophy

**「サービス = ロール = タグ」**を中心に据えた **role-per-service** 構造。

各サービス（Traefik、CoreDNS、Immich…）は Ansible ロールとして独立し、`site.yml` 内で 1 プレイ・1 タグに対応する。ロール内には Docker Compose、設定テンプレート、Vault 秘密が同居し、サービスを単位とした追加・差し替え・削除が、外部（site.yml / Makefile / CI）への配線追加を最小限にして完結する。

クラウドリソース（LangFuse 用 S3/IAM）は Ansible とは別系統として `tofu/` に分離し、ホスト側と AWS 側を疎結合に保つ（バックアップ用 S3/IAM は tofu 管理外・手動作成で、接続情報は backup ロールの Vault が持つ）。

## Directory Patterns

### Ansible エントリポイント
**Location**: `ansible/`  
**Purpose**: `ansible.cfg`、`site.yml`、`requirements.yml`、`group_vars/`、`inventories/local/` を保持する Ansible 実行のルート  
**Example**: `ansible/site.yml` は各ロールを `tags:` 付きで 1 プレイずつ宣言し、Make / CI からのタグ指定で部分実行する

### サービスロール
**Location**: `ansible/roles/<role>/`  
**Purpose**: 1 サービスのすべての知識（タスク、テンプレート、デフォルト変数、Vault、ハンドラ）を 1 ディレクトリに閉じ込める  
**Example**: 標準サブディレクトリは `defaults/ handlers/ tasks/ templates/ vars/`。Vault 暗号化値は `vars/vault.yml`、平文デフォルトは `defaults/main.yml`、Compose は `templates/docker-compose.yml.j2`

### 横断変数 / インベントリ
**Location**: `ansible/group_vars/local.yml`, `ansible/inventories/local/hosts`  
**Purpose**: 複数ロールで共有する値（FQDN、共有 Docker ネットワーク名、ターゲットホスト定義）  
**Example**: `traefik_network_name: traefik-public`、`*_traefik_host` 系の FQDN 群はここに集約される

### クラウド IaC
**Location**: `tofu/`  
**Purpose**: LangFuse 用の AWS S3（event/media/export）と IAM を OpenTofu で宣言。Ansible からは独立して `cd tofu && make plan/apply` で操作する（バックアップ用 S3 は tofu 管理外）  
**Example**: `main.tf` で AWS provider、`s3.tf`/`iam.tf` でリソース、`outputs.tf` で Ansible Vault 投入用のクレデンシャル出力

### CI/CD
**Location**: `.github/workflows/`  
**Purpose**: PR 時の Lint（`ansible_lint.yml`）とドキュメント整合性チェック（`docs_check.yml`）、`main` push 時の自動デプロイ（`deploy.yml`）  
**Example**: deploy ワークフローは変更ファイルパスから対象ロールを抽出し、許可リストで検証してから Tailscale 経由で SSH 実行

### 運用ドキュメント
**Location**: `docs/`、`ansible/roles/<role>/README.md`、`tofu/README.md`  
**Purpose**: 運用手順書（初期構築・バックアップリストア・DNS・障害対応）とロール別ドキュメント。「1 つの事実は 1 箇所」の担当境界で管理する（入口はルート README のドキュメントマップ）  
**Example**: 障害対応で得た恒久知見は `docs/troubleshooting.md` か該当ロール README の「運用上の注意」へ昇格する

### ドキュメント整合性チェック
**Location**: `scripts/check_docs.py`、`.github/workflows/docs_check.yml`  
**Purpose**: site.yml / Makefile / deploy.yml / README 群の整合を PR 時に機械検証する  
**Example**: ロール追加の 5 点セット漏れ・Markdown リンク切れ・監視対象コンテナ名の誤りを exit 1 で検出

### 二層 Makefile
**Location**: `/Makefile`（ホスト + 開発機共用）、`tofu/Makefile`（OpenTofu 専用）  
**Purpose**: 同じ語彙でローカル/リモートを切り替える。`<role>` がサーバ上直接実行、`deploy-<role>` が開発機からの SSH 経由実行  
**Example**: `make immich` ↔ `make deploy-immich`（同じロールを別レイヤから起動）

## Naming Conventions

- **ロールディレクトリ**: 全て小文字・単一トークン（例: `app`, `coredns`, `litellm`, `langfuse`, `observability`, `backup`）
- **タグ**: ロールディレクトリ名と必ず一致させる（site.yml の `tags:` と Makefile / CI で同一の語彙を共有する）
- **Ansible 変数**: snake_case で、必ず **ロール名プレフィックス** を付ける（`app_install_dir`, `traefik_image`, `traefik_acme_email` 等）。横断変数は対象サービス名プレフィックスを保つ（例: `app_traefik_host`）
- **テンプレート拡張子**: 出力ファイル名 + `.j2`（例: `docker-compose.yml.j2`, `nginx.conf.j2`, `Corefile.j2`）
- **ハンドラ命名**: 日本語の動詞句で人間可読に（例: `App を再起動`, `Systemd-resolved を再起動`）
- **インストール先**: `/opt/<role>/`（例: `/opt/traefik`, `/opt/app`, `/opt/backup`）

## Import / Inclusion Organization

Ansible のためコード import 概念は薄いが、ロール内・ロール間の参照規律を以下に揃える。

```yaml
# 1. Vault は各ロール冒頭で明示的に読み込む
- name: Vault 暗号化変数を読み込み
  ansible.builtin.include_vars:
      file: vault.yml

# 2. テンプレートは role-relative パスで参照（templates/ 配下）
- name: Docker-compose.yml を配置
  ansible.builtin.template:
      src: docker-compose.yml.j2
      dest: '{{ <role>_install_dir }}/docker-compose.yml'

# 3. クロスロール参照は group_vars/local.yml の横断変数経由（直接他ロールの vars を読まない）
```

**変数の解決順**:
1. `group_vars/local.yml`（クロスロール共有値）
2. `roles/<role>/defaults/main.yml`（平文デフォルト）
3. `roles/<role>/vars/vault.yml`（暗号化された上書き値）

## Code Organization Principles

- **ロール独立性**: あるロールの実装は他ロールの `tasks/` や `templates/` を直接参照しない。共有が必要な値は `group_vars/local.yml` に昇格する
- **Docker Compose は templates/ にのみ**: Compose 定義は必ず Jinja2 化（`docker-compose.yml.j2`）し、ロール変数で差分を吸収する
- **変更通知は handlers 経由**: テンプレート更新時はタスクから `notify:` で handlers/main.yml の再起動ハンドラを発火する（タスク内で直接 `docker compose restart` を呼ばない）
- **ロールの追加は 5 点セットで同時更新**: (1) `site.yml` にプレイ追加、(2) `Makefile` に `<role>` / `deploy-<role>` ターゲットと `.PHONY` を追加、(3) `.github/workflows/deploy.yml` のロール列挙 5 箇所に追加、(4) `roles/<role>/README.md` を作成、(5) `ansible/README.md` のロール一覧表へ追加。漏れは docs check CI が検出する（正確な手順は `ansible/README.md` の「ロールの追加方法」が正）
- **`vars/vault.yml` は直接 main へ push 可**: 暗号化済みのため、ブランチ運用の例外として直接 push が許可される（`CLAUDE.md` のブランチ戦略を参照）

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
