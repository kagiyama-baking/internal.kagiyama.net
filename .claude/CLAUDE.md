# CLAUDE.md

## プロジェクト概要

UTM上のUbuntu Server環境をAnsibleで管理するためのリポジトリ。

## ブランチ戦略

- メインブランチ: `main`
- 作業ブランチから `main` へのPRを経てマージする
- READMEなど影響の少ないファイルのみ、直接 `main` にpush可
- ブランチプレフィックス: `feature/`、`fix/`、`refactor/`、`docs/` 等

## Python 依存管理

- Python パッケージの管理には必ず **uv** を使用する
- `pip install` は使わず、`uv add`、`uv sync`、`uv run` 等を使うこと
- 例: `uv add yamllint ansible-lint` / `uv run yamllint ansible/`

## ドキュメント

- ロールやMakeターゲットの追加・変更時は、README.md（ルート・ansible/）が最新か確認し、必要に応じて更新すること

## デプロイ

プロジェクトルートの `Makefile` から `make deploy-*` で実行。
詳細は [README.md](README.md) を参照。
