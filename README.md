# 鍵山製パン 自宅サーバシステム

[![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Tailscale](https://img.shields.io/badge/Tailscale-0D4197?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com/)
[![Make](https://img.shields.io/badge/Make-6D00CC?style=for-the-badge&logo=gnu&logoColor=white)](https://www.gnu.org/software/make/)
[![SSH](https://img.shields.io/badge/SSH-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.openssh.com/)

## 概要

UTM上で構築したUbuntu Server環境を管理するためのAnsibleプレイブック群です。
Ansibleを使用して、サーバのセットアップや構成管理を自動化します。

## 環境

- ホストマシン: Mac mini (2018)
- ゲストマシン: Ubuntu Server 22.04.4 (UTM上)

## 初期セットアップ

1.  UTMをインストール

    https://mac.getutm.app/ からUTMをダウンロードしてインストールする。

2.  ISOイメージのダウンロード

    ここでは、Ubuntu Server 22.04.4を使用。
    https://ubuntu.com/download/server からダウンロードできる。

3.  UTMでUbuntu Server 22.04.4をインストール

    ネットワーク設定は「ブリッジモード」を選択すること。

4.  パッケージのアップデート

    ```bash
    sudo apt update
    sudo apt upgrade -y
    ```

5.  Tailscaleのインストール

    ```bash
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale up
    ```

    表示されるURLをブラウザで開き、認証を完了する。

    ```bash
    # IPv4/6 forwarding を有効化

    sudo sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf

    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    ```

    ```bash
    # UDP GRO forwarding を設定（パフォーマンス改善）
    sudo ethtool -K enp0s1 rx-udp-gro-forwarding on rx-gro-list off

    sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale > /dev/null <<'EOF'
    #!/bin/sh
    ethtool -K enp0s1 rx-udp-gro-forwarding on rx-gro-list off
    EOF
    sudo chmod +x /etc/networkd-dispatcher/routable.d/50-tailscale

    ```

    ```bash
    # Tailscaleをサブネットルーターとして設定
    sudo tailscale up \
    --advertise-routes=172.17.2.0/24 \
    --accept-routes \
    --ssh
    ```

    管理画面で internal の Subnet を Approve する。

6.  Gitのインストール

    ```bash
    sudo apt install -y git
    ```

7.  Ansibleのインストール

    ```bash
    sudo apt install -y pipx             # pipxをインストール
    pipx install ansible --include-deps  # Ansibleとその依存関係をインストール
    pipx ensurepath                      # パスを通す
    source ~/.bashrc                     # シェルを再読み込みしてpipxのパスを反映
    ```

8.  Makeをインストール

    ```bash
    sudo apt install -y make # Makefileを使用するために必要
    ```

9.  SSHキーの生成と登録

    SSHキーを生成する。

    ```bash
    ssh-keygen -t ed25519 -C "your_email@example.com"
    ```

    公開鍵を表示し、GitHubに登録する。

    ```bash
    cat ~/.ssh/id_ed25519.pub
    ```

    表示された公開鍵をコピーし、GitHub の **Settings > SSH and GPG keys > New SSH key** から登録する。

10. このリポジトリをcloneする

    ```bash
    git clone git@github.com:kagiyama-baking/internal.kagiyama.net.git # SSHでクローン
    cd internal.kagiyama.net                                           # クローンしたリポジトリに移動
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
SSH_HOST ?= internal.kagiyama.net      # ~/.ssh/config のホスト名
REMOTE_DIR ?= ~/internal.kagiyama.net  # サーバ上のリポジトリパス
```

### コマンド一覧

| コマンド              | 説明                                           |
| --------------------- | ---------------------------------------------- |
| `make deploy-test`    | テスト用プレイブックのみ実行                   |
| `make deploy-setup`   | セットアップを実行（sudo パスワード入力あり）  |
| `make deploy-coredns`   | CoreDNS をデプロイ（Vault パスワード入力あり） |
| `make deploy-portainer` | Portainer をデプロイ                           |
| `make deploy-check`     | ドライラン（変更を適用せず確認のみ）           |

ホスト名を一時的に変更して実行することもできます。

```bash
make deploy-test SSH_HOST=my-server
```
