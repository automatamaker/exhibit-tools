# exhibit-tools — 科学館展示アーケード機のセットアップ用ツール

無料ゲーム展示機（全21台・ゲーム8種）を、git を正本に「1台ずつ・その機体専用」に
仕立てるためのスクリプト集。クローン由来の重複値の解消、キオスク硬化、ゲームの
配線、オーバーレイ保護までを一連で行う。

## 前提と全体像

- **ハード/OS**: Raspberry Pi 5 / Debian 13 (trixie) / labwc(wayland) + wf-panel-pi。筐体ユーザは `game`。
- **ゲーム8種**: earth_defender / mohs_code / deep_earth / cloud_buster / gravity_meteor /
  ryuhyo_jump / aqua_solitaire / four_seasons（基本各3台、2台/1台のものもある）。
- **git**: 各ゲームは `github.com/automatamaker/<ゲーム名>` を正本とする。exhibit-tools も同 org。
- **クローン機に claude code は不要**。セットアップは自己完結スクリプト（対話メニュー）で行う。
- **オーバーレイFS**（raspi-config方式）で展示中はSDを読取専用保護。設定変更時だけOFFにする。

各ゲームは「完成版がある1台（完成機）」から git に公開し（**publish**）、残りの機体は
そこから取得して各機専用に仕立てる（**provision**）。

## 使い方 A: 完成機 — ゲームを git に公開する（各ゲーム1回）

完成版ゲームを持つ機体で、そのゲームを正本として公開する。

> **完成機は claude が入っているので automode が最短**: `cd ~/exhibit-tools && git pull` の後 claude を
> automode 起動し「この機を <ゲーム> の1号機にして」と伝えるだけで、下記 A＋B 相当を全自動で行う
> （手順は `CLAUDE.md`）。以下は手動でやる場合の参照。

```bash
# 0) オーバーレイをOFF（既にOFFならスキップ）。反映のため一度再起動。
sudo raspi-config nonint disable_overlayfs && sudo reboot

# 1) exhibit-tools を取得/更新
git clone https://github.com/automatamaker/exhibit-tools.git   # 初回。以降は git pull
cd exhibit-tools

# 2) まず内容確認（非破壊。何も書かず/pushしない）
bash publish_game.sh --dry-run ~/earth_defender

# 3) 本番公開（確認プロンプトあり）
bash publish_game.sh ~/earth_defender
```

`publish_game.sh` は自動で: `.gitignore` 整備（ログ/`__pycache__`/`.venv`/実行時スコアを除外）→
`requirements.txt` 検出/整備（pygame/pymunk/numpy 等の依存を記録）→ `games.conf` に起動方法を
登録 → `github.com/automatamaker/<ゲーム名>` を作成して push → `games.conf` を exhibit-tools に push。

> 公開後、その完成機自身も展示機にするなら、続けて「使い方 B」を実行する（ゲームは既に
> あるので clone は走らない）。

## 使い方 B: クローン機（2号機以降・claude なし） — 貼り付け1回

クローン機は claude 未導入。**exhibit-tools は public** なので、ターミナルに1行貼るだけで開始できる。

```bash
# 0) オーバーレイが ON なら OFF にして再起動（反映のため）。既に OFF なら不要。
sudo raspi-config nonint disable_overlayfs && sudo reboot

# 1) セットアップ開始（コピペ or 手打ち1回）
bash <(curl -fsSL https://raw.githubusercontent.com/automatamaker/exhibit-tools/master/bootstrap.sh)
```

`bootstrap.sh` が exhibit-tools を取得/更新して `setup.sh` を起動する。以降は対話に従うだけ:
①ゲームを番号で選ぶ → ②号機番号(02/03) → ③ゲームを最新へ更新（`~/<ゲーム>` が古い版なら
`.old.<日時>` へ退避して最新を clone、無ければ clone、git 管理下なら pull）→ ④依存を確認、
不足なら `.venv` を作って導入 → **最終確認1回** → ⑤autostart を `run_game.sh <ゲーム>` に配線 →
⑥`freegame_setup.sh` で固有値再生成＋キオスク硬化 → ⑦オーバーレイON→再起動。

> **ゲームrepo の可視性**: クローン機に gh が無く最新を git 取得するため、**展開中はゲームrepoも public**
> にする（`publish_game.sh` は既定 public で作成）。**全台の展開が終わったら private に戻してよい**
> （既設機はローカル起動なので影響なし。ただし後日デプロイ済み機へ修正を配るときは一時的に public が要る）。

再起動後、`bash check_identity.sh` で他機と固有値が異なることを確認できる。

### 機体名の規約

`<ゲーム名>-NN`（例 `earthdefender-01` / `mohscode-02`）。LAN上で「どの機体がどのゲームの
何号機か」が名前で分かる。ホスト名にアンダースコアは使えない（RFC1123/mDNS）ため `_` は自動除去。
**同じゲームの号機番号がダブらないよう、台↔名前の対応表を手元で管理すること**（スクリプトは
全台を横断で把握できない）。

## スクリプト一覧

| ファイル | 役割 |
|---|---|
| `publish_game.sh` | 【完成機】ゲームを git 化して `automatamaker/<game>` に公開。依存と起動方法も記録。`--dry-run` 可 |
| `setup.sh` | 【各機】ゲーム/号機を選び、取得・依存導入・autostart配線・固有値再生成・硬化・overlay ON・再起動を1本で。`--dry-run` 可 |
| `run_game.sh` | 展示機の autostart から呼ばれ、`games.conf` を見てゲームを起動（`.sh`はそのまま/`.py`はvenv優先） |
| `fix_double_launch.sh` | 旧版で二重起動になった機体の後始末。我々が入れた run_game 配線だけ除去し機体本来の起動を残す。可逆 |
| `wifi_prefer_24g.sh` | 指定SSID(既定 automaton)のWiFiを 2.4GHz(band=bg) に固定＝遅い5G回避。setup.sh が自動実行。単体でも可 |
| `games.conf` | 各ゲームの起動方法一覧（publish_game.sh が登録）。setup.sh / run_game.sh が参照 |
| `freegame_setup.sh` | hostname・machine-id・SSHホスト鍵を各機ごとに再生成し、最後に `kiosk_harden.sh` を適用。`-y`で確認省略 |
| `kiosk_harden.sh` | パネルの `connect`/`bluetooth`/`updater` ウィジェットだけを除去。パネル本体・スタートメニュー・WiFiアイコン(netman)は残す。冪等・`--revert`可 |
| `check_identity.sh` | hostname / machine-id / SSH鍵指紋 / CPUシリアル / MAC を表示（読み取り専用の診断） |

## 背景: なぜ固有値の再生成が要るか

無料ゲーム機は前の機体を1台ずつクローンして作ったため、本来ユニークであるべき値が重複している：

- **ホスト名**（同じ → 同一LAN上で識別できない）
- **machine-id**（同じ → DHCP リース衝突・journald 異常）
- **SSH ホスト鍵**（同じ → セキュリティ上 NG・接続警告）

これらを各機で作り直すのが `freegame_setup.sh`。ハード固有値（CPUシリアル・MAC）はクローンでも
必ず異なるので、`check_identity.sh` で重複判定の基準に使える。

> **データ永続化（スコア・設定）について**: スコアや音量を保存する無料ゲームは、ゲーム側で
> `/boot/firmware`（overlayFS の対象外パーティション）に書く実装のため、overlay を有効化しても残る。
> 本ツールはデータ永続化には関与しない。

## キオスク硬化（kiosk_harden.sh）

ゲーム実行中に更新通知・Bluetooth・RPi Connect のダイアログが前面に出るのを、根本（出させない）で防ぐ。

- **何をするか（外科的最小化）**: 上部パネル（wf-panel-pi）とデスクトップは**残したまま**、
  ダイアログを出すウィジェットだけを `~/.config/wf-panel-pi/wf-panel-pi.ini`（システム既定
  `/etc/xdg/wf-panel-pi/wf-panel-pi.ini` を上書き）から除去する。除去対象は
  `connect`（RPi Connect）・`bluetooth`・`updater`（更新通知）。
- **WiFiアイコン(netman)・スタートメニュー・時計・音量・電源・USB取り出しは温存**。各地に分散
  設置したとき現地でWiFi接続先を選べる必要があるため。CLI派は `sudo nmtui` でも可。
- **WiFiは切れない**: NetworkManager デーモンが常駐し保存接続（psk平文システム保存）を自律再接続する。
- 反映は次回 labwc セッション開始（再起動/再ログイン）から。稼働中に即反映は `pkill -x wf-panel-pi`。
- クローンで焼き込まれた Chromium のシングルトン残骸も掃除する（パネルの地球儀で Chromium が開かない事象の防止）。
- `bash kiosk_harden.sh --revert` で既定パネルへ戻す。

## 注意

- `setup.sh` / `publish_game.sh` は**オーバーレイOFF（書込可）**の状態で実行すること。
- ゲームrepo は展開中は **public**（`publish_game.sh` 冒頭 `VISIBILITY`。クローン機が無認証で最新取得するため）。
  全台展開後に private へ戻してよい。exhibit-tools 自体も public。
- `game02` は開発機であり、展示時は別途コインゲーム化する（本リポジトリ外の手順）。無料機21台には含まない。
- コイン機（有料ゲーム）の展開には別途 overlay + /data パーティションの手順がある（本リポジトリ外）。
