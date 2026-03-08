# UTMサーバ環境 `internal.kagiyama.net` 構築

## 環境

- ホストマシン: Mac mini (2018)
- ゲストマシン: Ubuntu Server 22.04.4 (UTM上)

## 初期セットアップ

1. UTMをインストール

    https://mac.getutm.app/ からUTMをダウンロードしてインストールする。

2. ISOイメージのダウンロード

    ここでは、Ubuntu Server 22.04.4を使用。
    https://ubuntu.com/download/server からダウンロードできる。

3. UTMでUbuntu Server 22.04.4をインストール

    ネットワーク設定は「ブリッジモード」を選択すること。

4. パッケージのアップデート

    ```bash
    sudo apt update
    sudo apt upgrade -y
    ```

5. Tailscaleのインストール

    ```bash
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale up
    ```

    表示されるURLをブラウザで開き、認証を完了する。

6. Gitのインストール

    ```bash
    sudo apt install -y git
    ```

7. SSHキーの生成と登録

    SSHキーを生成する。

    ```bash
    ssh-keygen -t ed25519 -C "your_email@example.com"
    ```

    公開鍵を表示し、GitHubに登録する。

    ```bash
    cat ~/.ssh/id_ed25519.pub
    ```

    表示された公開鍵をコピーし、GitHub の **Settings > SSH and GPG keys > New SSH key** から登録する。

    SSHキーのパスフレーズを毎回入力しなくて済むように、ssh-agentに鍵を登録する。

    ```bash
    eval "$(ssh-agent -s)"    # ssh-agentを起動
    ssh-add ~/.ssh/id_ed25519 # 秘密鍵をエージェントに登録（初回のみパスフレーズ入力）
    ```

    ログイン時に自動でssh-agentが起動するように、`~/.bashrc` の末尾に以下を追記する。

    ```bash
    # ssh-agent自動起動
    if [ -z "$SSH_AUTH_SOCK" ]; then
        eval "$(ssh-agent -s)" > /dev/null
        ssh-add ~/.ssh/id_ed25519 2>/dev/null
    fi
    ```

8. このリポジトリをcloneする

    ```bash
    git clone git@github.com:kagiyama-baking/internal.kagiyama.net.git # SSHでクローン
    cd internal.kagiyama.net                                           # クローンしたリポジトリに移動
    ```

9. Ansibleのインストール

    ```bash
    sudo apt install -y pipx             # pipxをインストール
    pipx install ansible --include-deps  # Ansibleとその依存関係をインストール
    pipx ensurepath                      # パスを通す
    source ~/.bashrc                     # シェルを再読み込みしてpipxのパスを反映
    ```

10. Makeをインストール

    ```bash
    sudo apt install -y make # Makefileを使用するために必要
    ```

11. テスト用プレイブックを実行して動作確認

    ```bash
    cd ansible # ansibleディレクトリに移動
    make test  # テスト用プレイブックを実行
    ```

## 開発機からのデプロイ

サーバにログインせずに、開発機から直接 Ansible を実行できます。
プロジェクトルートの Makefile が `git push` → SSH で `git pull` → Ansible 実行 をワンコマンドで行います。

### 前提条件

- 開発機からサーバへ SSH 接続できること（`~/.ssh/config` を設定推奨）
- サーバ上にこのリポジトリが clone 済みであること

### SSH 接続先の設定

Makefile 内のデフォルト値を環境に合わせて変更するか、実行時に指定してください。

```makefile
SSH_HOST ?= ubuntu-server              # ~/.ssh/config のホスト名
REMOTE_DIR ?= ~/internal.kagiyama.net  # サーバ上のリポジトリパス
```

### コマンド一覧

| コマンド            | 説明                                          |
| ------------------- | --------------------------------------------- |
| `make deploy-test`  | テスト用プレイブックのみ実行                  |
| `make deploy-setup` | セットアップを実行（sudo パスワード入力あり） |
| `make deploy-check` | ドライラン（変更を適用せず確認のみ）          |

ホスト名を一時的に変更して実行することもできます。

```bash
make deploy-test SSH_HOST=my-server
```
