# exhibit-tools — 科学館展示アーケード機のセットアップ用ツール

クローンで増やしたラズパイ筐体を、1台ずつ「その機体専用」に初期化するための
スクリプト集。

## 背景

無料ゲーム機（21台）は、前の機体を1台ずつクローンしながら作ったため、
本来ユニークであるべき値が重複している：

- **ホスト名**（同じ → 同一LAN上で識別できない）
- **machine-id**（同じ → DHCP リース衝突・journald 異常）
- **SSH ホスト鍵**（同じ → セキュリティ上 NG・接続警告）

これらを各機で作り直すのが `freegame_setup.sh`。あわせて、ゲーム実行中に
WiFi 接続先を尋ねるウィンドウ等が前面に出て操作不能になる事象を根本から防ぐ
**キオスク硬化**（`kiosk_harden.sh`）も同時に適用する（1回の実行で完了）。

> **データ永続化（スコア・設定）について**: スコアや音量を保存する無料ゲームは、
> ゲーム側で `/boot/firmware`（overlayFS の対象外パーティション）に書く実装に
> なっており、overlay を有効化しても残る。**このツールはデータ永続化には関与せず、
> 固有設定の作り直しだけを行う。** `/data` パーティションの追加も不要。

## 使い方（各機で1回）

```bash
git clone <このリポジトリのURL>          # 初回。2回目以降は git pull
cd exhibit-tools

# 現状の固有値を確認（重複していないか・読み取り専用）
bash check_identity.sh

# 固有値を作り直す（ホスト名は CPU シリアルから自動生成）
sudo bash freegame_setup.sh
#   ホスト名を明示したい場合:
#   sudo bash freegame_setup.sh pinball-01

sudo reboot
```

再起動後にもう一度 `bash check_identity.sh` を実行し、他機と値が異なることを確認する。

## スクリプト

| ファイル | 役割 |
|---|---|
| `check_identity.sh` | hostname / machine-id / SSH鍵指紋 / CPUシリアル / MAC を表示（読み取り専用の診断） |
| `freegame_setup.sh` | hostname・machine-id・SSHホスト鍵を各機ごとに再生成し、最後に `kiosk_harden.sh` を適用 |
| `kiosk_harden.sh` | ゲーム上に出る WiFi/認証ダイアログの源（RPi標準パネル wf-panel-pi 等）を停止。冪等・`--revert` 可 |

## キオスク硬化（kiosk_harden.sh）

ゲーム実行中に「WiFi 接続先を尋ねるウィンドウ」が前面に出て、キーボード/マウスの
無い筐体で操作不能になる事象の根本対策。`freegame_setup.sh` から自動で呼ばれるので
通常は個別実行不要だが、単体でも使える。

```bash
sudo bash kiosk_harden.sh            # 適用（freegame_setup.sh が内部で実行）
bash kiosk_harden.sh --revert        # 元に戻す
```

- **何をするか**: `/etc/xdg/labwc/autostart` の `wf-panel-pi`（WiFi/ネットワークUIの源）と
  `pcmanfm-pi`（デスクトップ）をコメントアウトし、polkit 認証エージェントを
  `~/.config/autostart` で Hidden 化する。`kanshi`（画面）・`pwrkey`（電源キー無効化）・
  `autotouch`（タッチ構成）等の筐体必須は温存。
- **WiFi は切れない**: NetworkManager デーモンは別に常駐し、保存接続（psk-flags=0=平文
  システム保存）を自律再接続するため。パネルは「表示」役にすぎない。
- 原本は `/etc/xdg/labwc/autostart.orig` に退避。反映は次回 labwc セッション開始
  （再起動 or 再ログイン）から。

## 注意

- `freegame_setup.sh` はゲーム本体・ゲーム選択 autostart には触らない（固有値の再生成と
  キオスク硬化のみ）。
- ハード固有値（CPUシリアル・MAC）はクローンでも必ず異なるので、重複判定の基準に使える。
- コイン機（有料ゲーム）の展開には別途 overlay + /data パーティションの手順がある（本リポジトリ外）。
