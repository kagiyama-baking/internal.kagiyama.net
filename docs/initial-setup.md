# サーバ初期構築

UTM 上に Ubuntu Server を新規構築し、Ansible 管理下に置くまでの手順。
既存サーバの**全損からの復旧（再構築 + データリストア）**もこの手順を基点とする。

現行本番: Ubuntu Server 24.04 LTS（Mac mini 2018 上の UTM ゲスト）。再構築時も最新 LTS を使用する。

## 1. VM の作成

1. [UTM](https://mac.getutm.app/) をダウンロードしてインストールする
2. [Ubuntu Server](https://ubuntu.com/download/server) の ISO（最新 LTS）をダウンロードする
3. UTM で Ubuntu Server をインストールする。ネットワーク設定は**「ブリッジモード」**を選択すること

## 2. OS 基本設定

```bash
sudo apt update
sudo apt upgrade -y
```

## 3. Tailscale の導入

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

表示される URL をブラウザで開き、認証を完了する。

```bash
# IPv4/6 forwarding を有効化
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf

sudo sysctl -w net.ipv6.conf.all.forwarding=1
echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
```

```bash
# UDP GRO forwarding を設定（パフォーマンス改善）
# インターフェース名（enp0s1）は環境により異なる。`ip a` で確認すること
sudo ethtool -K enp0s1 rx-udp-gro-forwarding on rx-gro-list off

sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale > /dev/null <<'EOF'
#!/bin/sh
ethtool -K enp0s1 rx-udp-gro-forwarding on rx-gro-list off
EOF
sudo chmod +x /etc/networkd-dispatcher/routable.d/50-tailscale
```

```bash
# Tailscale をサブネットルーターとして設定
sudo tailscale up \
--advertise-routes=172.17.2.0/24 \
--accept-routes \
--ssh
```

Tailscale 管理画面で internal の Subnet を Approve する。

## 4. ツールの導入

```bash
sudo apt install -y git make

# Ansible は pipx でインストール
sudo apt install -y pipx
pipx install ansible --include-deps
pipx ensurepath
source ~/.bashrc
```

## 5. リポジトリの取得

```bash
# SSH キーを生成し、GitHub（Settings > SSH and GPG keys）に公開鍵を登録する
ssh-keygen -t ed25519 -C "your_email@example.com"
cat ~/.ssh/id_ed25519.pub

git clone git@github.com:kagiyama-baking/internal.kagiyama.net.git
cd internal.kagiyama.net
```

## 6. Ansible コレクションの導入

プレイブックが使用するコレクション（community.general / community.docker / ansible.posix）を導入する。

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## 7. 疎通確認

```bash
make test # リポジトリルートで実行
```

## 8. 全ロールのデプロイ

前提: **vault パスワード**（復旧時はさらに **restic パスワード**）がパスワードマネージャ等から取り出せること。パスワードを失った状態での完全復旧はできない（[ansible/README.md](../ansible/README.md) の Vault 節参照）。

site.yml の定義順にデプロイする（すべてリポジトリルートで実行。開発機からは `make deploy-<ロール名>`）。

```bash
make setup          # sudo パスワード入力。Docker・ロケール・/opt 等の基盤
make coredns        # 以降 Vault パスワード入力（portainer を除く）
make traefik
make portainer
make immich
make observability
make app
make litellm
make langfuse
make backup
```

注意:

- `make setup` の daemon.json 反映は Docker デーモン再起動（= 全コンテナ再起動）を伴う（初回構築では影響なし）
- coredns デプロイ後、LAN クライアントの名前解決はルータ/端末の DNS 設定をこのサーバへ向けることで有効になる（[docs/dns.md](dns.md)）
- traefik の証明書取得には Route 53 用 IAM 認証情報（vault 内）が有効であること

## 9. データのリストア（復旧時のみ）

[docs/backup-restore.md](backup-restore.md) の手順で `immich-db` / `immich-library` / `app-db` を復元する。

バックアップ対象外のデータは手動で再設定する（[backup ロール README](../ansible/roles/backup/README.md) の対象外一覧を参照）:

- LiteLLM のモデル定義 → Web UI で再登録
- Portainer / Grafana の画面上の設定 → 必要に応じて再設定（Grafana のダッシュボード・アラートは Git 管理のためデプロイで復元される）
- Traefik の証明書 → 初回アクセス時に自動再取得（Let's Encrypt のレート制限に注意）

## 構築記録

- 2026-08 時点の本番実測: Ubuntu Server 24.04.4 LTS / kernel 6.8 系 / Docker 29.x + Compose v5.x
  （初回構築時は 22.04 LTS。その後 OS アップグレード済み）

## 関連ドキュメント

- [README.md](../README.md) — システム全体像とデプロイコマンド
- [docs/backup-restore.md](backup-restore.md) — リストア手順
- [docs/dns.md](dns.md) — DNS 設計と不変条件
