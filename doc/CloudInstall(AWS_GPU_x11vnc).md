# AWS EC2でGPU付きのインスタンスでROS開発環境をつくる(x11vnc版)
## はじめに
GPU付きインスタンスを作成できるAWSで、快適なROS開発環境が作れるかトライした。

Gazeboで、Realtime Factor 1.0、FPS 30～40程度が動作する環境を構築できた。

[VirtualGLを使った方法](CloudInstall(AWS_GPU).md)を以前にトライして良好な環境が得られたが、下記の課題があった。
- Gazeboなどの起動時に`vglrun gazebo`のように`vglrun`を入れる必要があった
- VirtualGLはOpenGLの機能を全て網羅していない（ただしGazeboとRvizは試した範囲内では問題なかった）

そこで、本稿では別の方法として`x11vnc`を使用する方法にトライした。
x11vncは仮想デスクトップではなく、実在するモニターにVNCを通してアクセスすするものである。
AWSにはモニターは無いが、仮想モニターをつくって対応させる。

こうすることで、ローカルマシンと全く同じ感覚で使用することができる。

欠点として、１インスタンスにつき、１ユーザーしか使用できなくなる。
VirtualGLを使った方法だと複数の仮想デスクトップをつくることで多数ユーザーにも容易に対応できるため、これはユースケースによって使い分けるべきところになる。

## インスタンスを作成する
AWSにはGPU付きのインスタンスが2種類ある。pから始まるタイプは機械学習など計算用、gから始まるタイプがグラフィック用である。
ここでは、「g2.2xlarge」を使用した例で説明する。

なお、GPU付きインスタンスは起動インスタンス数制限が0(1つも起動出来ない)になっている場合がある。その場合、制限の緩和をサポートへ依頼する必要がある。

OSイメージは標準で準備されたUbuntu16.04を選ぶ。インスタンスタイプでg2.2xlargeを選ぶ。あとはそのままの設定で良いが、ボリュームは変更した方が良い。標準では8GBであるため拡張する。20GB位なら良いだろう。

## まずはアップデート
```
#システムをアップデート
sudo apt-get update -y
sudo apt-get upgrade -y linux-aws
#再起動
sudo reboot
```
## インストールする
参考) https://docs.aws.amazon.com/ja_jp/AWSEC2/latest/UserGuide/install-nvidia-driver.html
```
#必要なパッケージをインストール
sudo apt-get install -y gcc make linux-headers-$(uname -r)

#標準のオープンソース版ドライバーを無効にする
cat << EOF | sudo tee --append /etc/modprobe.d/blacklist.conf
blacklist vga16fb
blacklist nouveau
blacklist rivafb
blacklist nvidiafb
blacklist rivatv
EOF

#カーネルパラメータでオープンソース版ドライバーを無効にする
cat <<EOF | sudo tee --append /etc/default/grub
GRUB_CMDLINE_LINUX="rdblacklist=nouveau"
EOF

#ブートローダーを再構築する
sudo update-grub


# NVIDIA製ドライバーをダウンロードする
# 適合するドライバーは　http://www.nvidia.com/Download/Find.aspx　から探す
# G2インスタンスの場合…Product Type:GRID、Product Series:GRID Series、Product:GRID K520、Operating System:Linux 64-bit
# 下記のリンクの[430.40]を修正すると最新バージョンにあわせられる

wget http://us.download.nvidia.com/XFree86/Linux-x86_64/430.40/NVIDIA-Linux-x86_64-430.40.run

# インストール実行
chmod +x NVIDIA-Linux*.run
sudo ./NVIDIA-Linux*.run		

# ウィーザードが動く
# [Continue installation]を押す
# WARNINGがでるがOKを押す
# 「Would you like to run the nvidia-xconfig～」→Noを押す

# X Windowの設定を変更 BusIDはlspciコマンドで確認できる。
sudo nvidia-xconfig -a --virtual=1280x1024 --allow-empty-initial-configuration --enable-all-gpus --busid PCI:0:3:0

# Desktop環境とx11vncをインストール
sudo apt install -y lubuntu-desktop
sudo apt install -y xterm gnome-terminal
sudo apt install -y x11vnc

# 再起動
sudo reboot
```


## VNCとスワップ領域の自動起動を設定する。
```
#VNCのパスワードを設定(ubuntu)
sudo x11vnc -storepasswd ubuntu /etc/x11vnc.pass

#ユーザーubuntuのパスワードを設定する(AWSは標準ではパスワード無しなので
sudo passwd ubuntu

#sudo x11vnc  -xkb -noxrecord -noxfixes -noxdamage -display :0 -auth /var/run/lightdm/root/:0 -rfbauth /etc/x11vnc.pass -rfbport 5900 -forever -loop -repeat -shared



cat << EOF | sudo tee /etc/systemd/system/x11vnc.service
[Unit]
Description=VNC Server
After=multi-user.target network.target

[Service]
Restart=always
ExecStart=/usr/bin/x11vnc -xkb -noxrecord -noxfixes -noxdamage -display :0 -auth /var/run/lightdm/root/:0 -rfbauth /etc/x11vnc.pass -rfbport 5900 -forever -loop -repeat -shared

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl start x11vnc.service


# スワップ領域を作成。
# Ephemeral Disk(揮発性ストレージ)を使うため
# 起動する度に作成する必要がある

cat << EOF | sudo tee /etc/systemd/system/swap.service
[Unit]
Description=SWAP Enabling

[Service]
Type=oneshot
Environment="MNT_PATH=/mnt" "SWAP_FILE=swapvaol" "DISK_DEV=/dev/xvdb"
ExecStartPre=/bin/umount \${MNT_PATH}
ExecStartPre=/sbin/wipefs -fa \${DISK_DEV}
ExecStartPre=/sbin/mkfs -t ext4 \${DISK_DEV}
ExecStartPre=/bin/mount -t ext4 \${DISK_DEV} \${MNT_PATH}
ExecStartPre=/bin/sh -c "/usr/bin/fallocate -l 16GB \${MNT_PATH}/\${SWAP_FILE}"
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


## 動作確認

次に、ローカルPCからTurboVNC Viewerを使ってアクセスする。

LXTerminalを開いて、下記を入力して動作確認をする。

```
firefox http://webglreport.com/
#「This browser supports WebGL 1」とでればOK

```


### (参考)ローカルPCの準備
ローカルPC側の準備をする。Windowsを想定する。
まず下記のソフトウェアをインストールする。
1. Tera Term( https://forest.watch.impress.co.jp/library/software/utf8teraterm/ )をインストール
2. TurboVNC Viewer( https://sourceforge.net/projects/turbovnc/ )をインストール

Tera TermでVPSサーバーにSSHで接続する。(参考 https://ttssh2.osdn.jp/manual/ja/usage/ssh.html )
ここでProxy環境下の場合は、先にProxyの設定をしておく。(参考 https://ttssh2.osdn.jp/manual/ja/usage/proxy.html )
AWSの場合、標準のユーザー名は「ubuntu」である。パスワードはない。
インスタンスを作成する際にキーファイルを作成しているはずなので、それを使ってログインする。
(参考 https://dev.classmethod.jp/cloud/aws/aws-beginner-ec2-ssh/)

ログインできたら、次にポート転送の設定をする。
1. Tera Termのメニュー　設定→SSH転送
2. 追加をクリック
3. 下記の通り設定する
 - ローカルのポート: `5900` (ローカルPCにVNCサーバーが入っている場合エラーが出る場合あり。その場合は5901にする)
 - リッスン: (空白)
 - リモート側のホスト: (空白)
 - ポート: `5900`
4. OK→OK

設定後、設定ファイルを保存しておくと便利である。
(参考 https://ttssh2.osdn.jp/manual/ja/setup/teraterm.html)

次に、TurboVNC Viewerを立ち上げる。
`127.0.0.1`と入力しConnectをクリックする。（上記でローカルポートを5901にした場合は127.0.0.1:1）

これでデスクトップが表示されるはずである。


## ROS環境のインストール
[README.md](../README.md)と同じ方法でROS環境を入れる。

## Trouble shooting
### しばらく放置するとブラックアウトする
スクリーンセーバーが稼働すると不具合が発生する。

左下のメニュー→Preferences→Light Locker Settings
- Enable light-locker　→　OFFに
- Screensaver → Xfce Power Managementで管理されているので、Openを押し、「Display」の「Handle display power management」をOFFにし、「Security」の「Automatically lock the session」を「Never」に

### 起動時に「システムプログラムの問題が見つかりました」
https://www.kwonline.org/memo2/2019/04/02/system-program-problem-detected-message-on-ubuntu/

## ポイント
nvidia-xconfigで仮想スクリーンを作成している。
