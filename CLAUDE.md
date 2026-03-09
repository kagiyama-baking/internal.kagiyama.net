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

## デプロイ

プロジェクトルートの `Makefile` から `make deploy-*` で実行。
詳細は [README.md](README.md) を参照。
