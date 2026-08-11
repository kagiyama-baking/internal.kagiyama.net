# Ansible

`internal.kagiyama.net` の構成管理を行う Ansible プレイブック。

## 構成の概要

- プレイブックは `site.yml` の 1 本のみ。**ロール = タグ = サービス**の単位で分割し、タグ指定で個別に実行する
- インベントリは `inventories/local/hosts`（`localhost` への local 接続）のみ。リモートへの適用はルート `Makefile` の `deploy-*` ターゲットが SSH 経由で行う
- **開発機で `ansible-playbook` や `make <ロール名>` を直接実行しないこと**。インベントリが localhost のため**開発機自身に適用される**。サーバへの適用は必ず `make deploy-*` を使う

依存コレクション（community.general / community.docker / ansible.posix）は初回に導入する。

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## ロール一覧

| ロール | 役割 | Vault | CD | README |
|---|---|:---:|:---:|---|
| test | 疎通確認 | – | – | [README](roles/test/README.md) |
| setup | OS 初期設定・Docker・`/opt` 作成 | – | – | [README](roles/setup/README.md) |
| coredns | 内部 DNS サーバ | ✓ | ✓ | [README](roles/coredns/README.md) |
| traefik | リバースプロキシ・Let's Encrypt | ✓ | ✓ | [README](roles/traefik/README.md) |
| portainer | Docker 管理 UI | – | ✓ | [README](roles/portainer/README.md) |
| immich | 写真・動画管理 | ✓ | ✓ | [README](roles/immich/README.md) |
| observability | 監視・ログ・アラート | ✓ | ✓ | [README](roles/observability/README.md) |
| app | kawashiro-server 本体 | ✓ | ✓ | [README](roles/app/README.md) |
| litellm | LLM ゲートウェイ | ✓ | ✓ | [README](roles/litellm/README.md) |
| langfuse | LLM トレーシング | ✓ | ✓ | [README](roles/langfuse/README.md) |
| backup | 自動バックアップ（→ AWS S3） | ✓ | ✓ | [README](roles/backup/README.md) |

- **Vault** = 実行時に Vault パスワードが必要（`Makefile` のターゲットに `--ask-vault-pass` 組み込み済み）
- **CD** = main マージ時の自動デプロイ対象（`.github/workflows/deploy.yml` の `ALLOWED_ROLES`。setup は sudo が必要、test はテスト用のため対象外）
- 各ロールのコンテナ構成・変数・**運用上の注意**はロール README を参照

## ディレクトリ規約

ロールは次の標準構成に従う（必要なディレクトリのみ持つ）。

```
roles/<ロール名>/
├── README.md        # ロールのドキュメント（必須。無いと docs check CI が失敗する）
├── defaults/        # 調整可能な変数（イメージタグ・ポート・リソース上限等）
├── vars/
│   ├── main.yml     # 平文の内部変数（vault 変数への参照を含む）
│   └── vault.yml    # 機密変数（ansible-vault 暗号化）
├── tasks/           # 冪等なタスク定義
├── handlers/        # 「<サービス名> を再起動」ハンドラ
├── templates/       # docker-compose.yml.j2 等の Jinja2 テンプレート
└── files/           # 静的ファイル（observability のダッシュボード JSON 等）
```

- 変数名は snake_case で `<ロール名>_` プレフィックス必須。機密変数は `<ロール名>_vault_` プレフィックス
- Docker Compose は必ず `templates/*.j2` で管理し、`/opt/<ロール名>/` に配置する（素の compose ファイルを置かない）
- 設定変更の反映は `notify` → ハンドラ経由で行う
- コンテナがデータの所有権を持つディレクトリは Ansible で作らない（Compose の初回起動に任せる）。`become` が必要な操作は setup ロールに寄せる

## ロールの追加方法

新しいロールは次の **5 点セット**を同時に更新する。漏れは docs check CI（`scripts/check_docs.py`）が検出する。

1. `roles/<ロール名>/` を上記規約で作成する（**README.md を含める**）
2. `site.yml` にプレイを追加する（`tags: <ロール名>`）
3. ルート `Makefile` に `<ロール名>` / `deploy-<ロール名>` の 2 ターゲットと `.PHONY` 登録を追加する
4. `.github/workflows/deploy.yml` のロール列挙 **5 箇所**（workflow_dispatch の default / `ALLOWED_ROLES` / `roles=` の echo ×2 / for ループ）に追加する
5. この README のロール一覧表と、ルート README のサービス構成表・コマンド表・アーキテクチャ図に追加する

あわせて次の 3 点も更新・判断すること。

- 初期構築手順: [docs/initial-setup.md](../docs/initial-setup.md) の「全ロールのデプロイ」の順序リストに追加する
- 監視: `observability_alert_containers`（[observability ロール](roles/observability/README.md)）に追加するか
- バックアップ: location を追加するか、[backup ロール README](roles/backup/README.md) の対象外表に理由付きで記載するか

## 共有変数（group_vars/local.yml）

複数ロールで共通して使用する変数は `group_vars/local.yml` を Single Source of Truth として管理する。

| 変数名 | 用途 |
|---|---|
| `traefik_network_name` | Traefik ネットワーク名（全公開サービス共有） |
| `portainer_traefik_host` | Portainer の FQDN（CoreDNS・Traefik 共用） |
| `immich_traefik_host` | Immich の FQDN（同上） |
| `grafana_traefik_host` | Grafana の FQDN（同上） |
| `app_traefik_host` | kawashiro-server の FQDN（同上） |
| `litellm_traefik_host` | LiteLLM の FQDN（同上） |
| `langfuse_traefik_host` | LangFuse の FQDN（同上） |

ホスト名を変更する際はこのファイルを編集すれば CoreDNS・Traefik に反映される。

> **既知の課題（SSoT の例外）:** 次の 3 変数には FQDN が直書きされており、この単一情報源から外れている。
> ホスト名変更時はこれらも修正が必要（修正は該当ロールの再デプロイ = CD 発火を伴う）。
>
> - `roles/app/defaults/main.yml` の `app_litellm_proxy_url`・`app_langfuse_base_url`
> - `roles/litellm/defaults/main.yml` の `litellm_langfuse_host`

## Ansible Vault

### 変数の規約

機密情報（IP アドレス・パスワード・API キー等）は各ロールの `vars/vault.yml` に `<ロール名>_vault_` プレフィックス変数として定義し、ansible-vault で暗号化して管理する。
機密でない設定は `vars/main.yml` や `defaults/main.yml` に平文で置き、vault 変数を参照する形にする（ホスト名の編集に vault 復号を不要にするため）。
`group_vars` ではなくロール内の `vars/` に置くことで、該当ロール実行時のみ Vault パスワードが要求される。

各ロールが持つ vault キーの一覧は、ロール README の「Vault 変数」節を参照。

### よく使うコマンド

`ansible/` ディレクトリ内で実行する。

| コマンド | 用途 |
|---|---|
| `ansible-vault encrypt <file>` | 平文ファイルを暗号化 |
| `ansible-vault edit <file>` | 復号して編集 → 保存時に再暗号化 |
| `ansible-vault view <file>` | 復号して閲覧（読み取り専用） |
| `ansible-vault rekey <file>` | Vault パスワードを変更 |

### 実行時

Vault を使用するロールの実行時は Vault パスワードが必要（Makefile のターゲットに `--ask-vault-pass` 組み込み済み）。
Vault 不要のロールは test / setup / portainer（それ以外の全ロールが `vars/vault.yml` を持つ）。

```bash
make coredns    # Vault パスワードの入力を求められる
make portainer  # Vault 不要、そのまま実行できる
```

### Vault パスワードの管理

- **保管**: パスワードマネージャを正とし、CI 用に GitHub Secrets `ANSIBLE_VAULT_PASSWORD` にも同じ値を設定する
- **CI への受け渡し**: `deploy.yml` が Secrets の値を一時ファイルとしてサーバへ scp し、`--vault-password-file` で使用後に trap で削除する（パスワードをコマンド引数に含めない）
- **喪失リスク**: vault の中身（特に restic パスワード）を失うとバックアップの復元が不可能になる。Vault パスワードは必ず複数箇所に保管する
- **ローテーション手順**:
    1. `ansible/` で `ansible-vault rekey roles/*/vars/vault.yml`（glob で vault を持つ全ロールが対象になる。旧 → 新パスワードを入力）
    2. GitHub Secrets `ANSIBLE_VAULT_PASSWORD` を新パスワードに更新
    3. パスワードマネージャを更新
    4. 任意の Vault 使用ロールを `make deploy-<ロール名>` で実行し、復号できることを確認

## 関連ドキュメント

- [README.md](../README.md) — システム全体構成・デプロイコマンド・CI/CD
- [docs/initial-setup.md](../docs/initial-setup.md) — 初期構築と全損復旧
- [docs/troubleshooting.md](../docs/troubleshooting.md) — 障害時の調査手順
