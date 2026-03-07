.PHONY: test setup all check

# すべてのプレイブックを実行する
all: test setup

# テスト用プレイブックを実行する（動作確認用）
test:
	ansible-playbook site.yml --tags test

# セットアップを実行する（Docker等のインストール、sudoパスワードが必要）
setup:
	ansible-playbook site.yml --tags setup --ask-become-pass

# ドライラン（実際には変更を適用せず、実行内容を確認する）
check:
	ansible-playbook site.yml --check --ask-become-pass
