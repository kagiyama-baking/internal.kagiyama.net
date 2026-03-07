# 自宅サーバ構築

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
