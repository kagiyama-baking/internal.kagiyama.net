# OpenTofu — LangFuse 用 AWS リソース管理

LangFuse が使用する AWS リソース（S3 バケット 3 つ + IAM ユーザー）を [OpenTofu](https://opentofu.org/) で宣言的に管理する。

> **Note:** このディレクトリが管理するのは **LangFuse 用リソースのみ**。
> バックアップ用の S3 バケット / IAM ユーザーは**管理対象外**（手動作成。接続情報は backup ロールの vault で管理）。

## 管理対象

| リソース | 定義 | 内容 |
|---|---|---|
| S3 バケット × 3 | `s3.tf` | event / media / export の 3 用途（名称は `variables.tf` の `project_prefix` から生成）。SSE 暗号化・パブリックアクセスブロック付き |
| IAM ユーザー | `iam.tf` | LangFuse から上記バケットのみ操作できる最小権限ユーザーとアクセスキー |

## ファイル構成

| ファイル | 内容 |
|---|---|
| `main.tf` | プロバイダー設定（AWS。リージョンは `variables.tf` 参照） |
| `s3.tf` | S3 バケット定義（`for_each` で 3 バケット） |
| `iam.tf` | IAM ユーザー・インラインポリシー・アクセスキー |
| `variables.tf` | 変数定義。**全変数に default があるため tfvars は不要** |
| `outputs.tf` | アクセスキー・バケット名の出力 |
| `Makefile` | 操作コマンド（下表） |

## 使い方

`tofu/` ディレクトリ内で実行する（ルートの Makefile とは独立）。

| コマンド | 説明 |
|---|---|
| `make init` | プロバイダーのインストール |
| `make plan` | 実行計画を確認（ドライラン） |
| `make apply` | リソースを作成・更新 |
| `make destroy` | リソースを削除 |
| `make output` | 出力値を表示 |
| `make secret` | シークレットアクセスキーを表示（Ansible vault 格納用） |
| `make fmt` | コードフォーマット |
| `make validate` | 構文チェック |

典型フロー: `make init` →（コード修正）→ `make fmt` → `make validate` → `make plan` で差分確認 → `make apply`。

## シークレットの受け渡し（LangFuse へ）

作成した IAM アクセスキーは LangFuse の vault に格納して使う。

```bash
cd tofu && make secret               # アクセスキーを表示
cd .. && ansible-vault edit ansible/roles/langfuse/vars/vault.yml
# langfuse_vault_s3_access_key_id / langfuse_vault_s3_secret_access_key に設定
make deploy-langfuse                 # 反映
```

## state 管理と注意（重要）

- backend を設定していないため、state は**このディレクトリのローカルファイル**（`terraform.tfstate`）
- state には **IAM アクセスキー等のシークレットが平文で含まれる**
- `.gitignore` で除外済み。**絶対にコミットしないこと**
- state は**この開発機にしか存在しない単一障害点**。`make apply` で state が変わったら、暗号化した上で退避すること（パスワードマネージャの添付ファイル等）
- state を失った場合もリソースは AWS 上に残る（管理から外れるだけ）。`tofu import` で state に再取得できる
- `make destroy` は LangFuse のイベント・メディアデータの消失を伴う。実行前に影響を確認すること

## 関連ドキュメント

- [README.md](../README.md) — システム全体像（インフラ管理の位置づけ）
- [langfuse ロール README](../ansible/roles/langfuse/README.md) — S3 を利用する側の設定
- [ansible/README.md](../ansible/README.md) — Vault の運用
