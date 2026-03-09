# CLAUDE.md

## プロジェクト概要

UTM上のUbuntu Server環境をAnsibleで管理するためのリポジトリ。

## ブランチ戦略

- メインブランチ: `main`
- 作業ブランチから `main` へのPRを経てマージする
- READMEなど影響の少ないファイルのみ、直接 `main` にpush可
- ブランチプレフィックス: `feature/`、`fix/`、`refactor/`、`docs/` 等

## デプロイ

プロジェクトルートの `Makefile` から `make deploy-*` で実行。
詳細は [README.md](README.md) を参照。
