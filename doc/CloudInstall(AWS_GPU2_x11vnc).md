# AWS EC2でGPU付きのインスタンスでROS開発環境をつくる(x11vnc版)
## はじめに
以前に[awsのGPUインスタンスで環境構築を行った](CloudInstall(AWS_GPU_x11vnc).md)際は、古いバージョンのインスタンス「g2.2xlarge」を使用していた。

そこでawsの新しいインスタンス(g4dn.xlarge)を使用した環境構築についてここに記す。

なお、GPU付きインスタンスは起動インスタンス数制限が0(1つも起動出来ない)になっている場合がある。
その場合、制限の緩和をサポートへ依頼する必要がある。
EC2のページの左メニュー「制限」の中から「All G instances のオンデマンドを実行中」を選び、vCPU数を4以上に緩和する。
今回のインスタンスはvCPUを4使うので、vCPU数4とすると１つのインスタンスが起動できるようになる。

OSイメージは標準で準備されたUbuntu16.04を選ぶ。インスタンスタイプでg2.2xlargeを選ぶ。あとはそのままの設定で良いが、ボリュームは変更した方が良い。標準では8GBであるため拡張する。20GB位なら良いだろう。

NVIDIAのドライバーインストールは頻繁にバージョンアップがあるので、まずawsのドキュメントを確認してほしい。

awsのアカウント作成からインスタンス作成までの流れは[aws_tutorial.pdf](aws_tutorial.pdf)に書いている。

## まずはアップデート
```
sudo apt update -y
sudo apt upgrade -y linux-aws

# grubのUpdateで選択しが表示された場合、 一番上、一番上

sudo reboot
```

## NVIDIAのドライバーをインストール
```
sudo apt-get install -y gcc make linux-headers-$(uname -r)

# https://docs.aws.amazon.com/ja_jp/AWSEC2/latest/UserGuide/install-nvidia-driver.html#nvidia-grid-g4
# インストール手順の詳細は上記を参照。ここではパブリックドライバーをインストールしています。
# 上記ページの内容は頻繁に変わります。上手いくいかないときは必ず上記を参照ください。

wget http://us.download.nvidia.com/tesla/450.51.05/NVIDIA-Linux-x86_64-450.51.05.run
chmod +x NVIDIA*.run
sudo ./NVIDIA*.run

# ウィーザードが動く
# [Continue installation]を押す
# WARNINGがでるがOKを押す
# 「Would you like to run the nvidia-xconfig～」→Noを押す

#busidの確認方法は nvidia-xconfig --query-gpu-info
sudo nvidia-xconfig -a --virtual=1280x1024 --allow-empty-initial-configuration --enable-all-gpus --busid PCI:0:30:0

cat << EOF | sudo tee --append /etc/modprobe.d/blacklist.conf
blacklist vga16fb
blacklist nouveau
blacklist rivafb
blacklist nvidiafb
blacklist rivatv
EOF

cat << EOF | sudo tee --append /etc/default/grub
GRUB_CMDLINE_LINUX="rdblacklist=nouveau"
EOF

sudo update-grub

sudo reboot
```

## Ubuntuデスクトップと必要なソフトをインストール
```
# Ubuntuデスクトップ環境
sudo apt install -y ubuntu-desktop
sudo apt install -y xterm
# VNCサーバー
sudo apt install -y x11vnc
# ブラウザーでVNCを表示するソフト
sudo snap install novnc

# 自動ログインを設定する
cat << EOF | sudo tee /etc/lightdm/lightdm.conf.d/01_autologin.conf
[SeatDefaults]
autologin-user=ubuntu
autologin-user-timeout=0
EOF

sudo reboot
```

## x11vncとnovncとスワップ領域の確保を自動起動で行う設定
```
#x11vnc
cat << EOF | sudo tee /etc/systemd/system/x11vnc.service
[Unit]
Description=VNC Server
After=multi-user.target network.target

[Service]
Restart=always
ExecStart=/usr/bin/x11vnc -xkb -noxrecord -noxfixes -noxdamage -display :0 -auth /var/run/lightdm/root/:0 -rfbport 5900 -forever -loop -repeat -shared

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl start x11vnc.service

#novnc
cat << EOF | sudo tee /etc/systemd/system/novnc.service
[Unit]
Description=noVNC Server
After=multi-user.target network.target x11vnc.service

[Service]
Restart=always
ExecStart=/snap/bin/novnc --listen 6080 --vnc localhost:5900

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable novnc.service
sudo systemctl start novnc.service


#スワップ領域
cat << EOF | sudo tee /etc/systemd/system/swap.service
[Unit]
Description=SWAP Enabling

[Service]
Type=oneshot
Environment="MNT_PATH=/mnt" "SWAP_FILE=swapvaol" "DISK_DEV=/dev/nvme1n1"
ExecStartPre=/sbin/wipefs -fa \${DISK_DEV}
ExecStartPre=/sbin/mkfs -t ext4 \${DISK_DEV}
ExecStartPre=/bin/mount -t ext4 \${DISK_DEV} \${MNT_PATH}
ExecStartPre=/bin/sh -c "/usr/bin/fallocate -l 32GB \${MNT_PATH}/\${SWAP_FILE}"
ExecStartPre=/bin/chmod 600 \${MNT_PATH}/\${SWAP_FILE}
ExecStartPre=/sbin/mkswap \${MNT_PATH}/\${SWAP_FILE}
ExecStart=/sbin/swapon \${MNT_PATH}/\${SWAP_FILE}
ExecStop=/sbin/swapoff -a
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable swap.service
sudo systemctl start swap.service
```

## GPUが有効か確認
firefoxで[http://webglreport.com/](http://webglreport.com/)を開いて、WebGLがサポートされているか確認する。

コマンドで確認する。Driverのバージョンなど情報が出ればOK。
```
nvidia-smi
```

## ROS環境のインストール
[README.md](../README.md)と同じ方法でROS環境を入れる。


## Visual Studio Codeのインストール
必要に応じて、Visual Studio Codeをインストールする。
```
sudo snap install --classic code
# code もしくは /snap/bin/code で起動できる
```

## Ubuntuデスクトップでの設定
### 日本語の設定
必要ならば日本語に設定を変える。

ここで、標準ではパスワードが設定されていないので、GUIで設定を変更するときにパスワードが求められてもパスワード認証に失敗してしまうため、パスワード設定をする。
```
sudo passwd ubuntu
```

- 設定⇒Language Support⇒Install⇒Install/Remove Languages⇒Japanese
  - 日本語をリストの一番上に持ってくる⇒Aplly system-wideをクリック
  - リブートするとディレクトリ名を日本語にするか聞かれるが古いままにする
- 右上の「En」⇒テキスト入力設定⇒入力ソースの下の「+」⇒日本語(Mozoc)(IBus)
  - 次のソースへの切り替え（半角全角キーはVNCで動作しないので）ctrl+Spaceを割り当てる

### その他の設定
いくつかそのままだと問題になる箇所があるので、設定を行う。

- 設定⇒Setting Brightness & Lock(画面の明るさとロック)
  - Turn screen off when inactive for(次の時間アイドル状態が続けば画面をオフにする): Never(しない)
  - Lock(ロック) : OFF(オフ)
  -  Require my password... (サスペンドからの復帰時にパスワードを要求する) : チェックなし
- 設定⇒Software & Updates (ソフトウェアとアップデート)⇒Update(アップデート)
  - Automatically check for updates(アップデートの自動確認) : Never(しない)
  - Notify me of a new Ubuntu version(Ubuntuの新バージョンの通知) : Never(しない)
- 右上の時計⇒時刻と日付の設定⇒Tokyoを選択


## トラブルシューティング
### upgradeしたら画面が出ない
LinuxカーネルやGRUBまわりのupgradeがあると、NVIDIAのドライバーが正常に動作しなくなる場合があります。

上記の[NVIDIAのドライバーをインストール](#NVIDIAのドライバーをインストール)をやり直してみてください。
awsのドキュメントの更新が無いか必ず確認してください。

### 起動時に「システムプログラムの問題が見つかりました」
crashログを消すと表示されなくなります。
```
sudo rm -rf /var/crash/*
```
