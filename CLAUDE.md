# exhibit-tools — Claude 運用手順（完成機セットアップ）

このリポジトリは科学館の展示アーケード機（Raspberry Pi 5 / Debian trixie / labwc）を
セットアップするツール群。**筐体ユーザ `game` で、`~/exhibit-tools` を作業ディレクトリに
claude を automode 起動**して使う想定。

## いつ何をするか

ユーザが「この機をセットアップして」「<ゲーム> の <N>号機にして」等と一言依頼したら、
**完成機のセットアップ**（＝そのゲームを git 公開し、この機体を展示キオスクに仕立てる）を
下記のとおり最後まで自動で行う。各ステップはこのリポジトリのスクリプトを呼ぶだけでよい。

対象ゲーム8種: `earth_defender / mohs_code / deep_earth / cloud_buster / gravity_meteor /
ryuhyo_jump / aqua_solitaire / four_seasons`。git は `github.com/automatamaker/<ゲーム名>`。

## 手順（この順番で実行）

1. **プリフライト（オーバーレイOFF確認）**
   `sudo raspi-config nonint get_overlay_now` を実行。
   - 結果が `1`（OFF＝書込可）ならそのまま次へ。
   - 結果が `0`（ON＝読取専用）なら書き込めない。`sudo raspi-config nonint disable_overlayfs`
     を実行し `sudo reboot`。「再起動後に claude を起ち上げ直して同じ依頼をしてください」と伝えて**停止**。

2. **ゲームを確定**
   - ユーザが指定したゲーム名を使う。未指定なら、`~` 直下に在る8種のゲームディレクトリを列挙し、
     現在の `~/.config/labwc/autostart` が起動している物も手掛かりに**候補を提示してユーザに確認**する。
     推測で先に進めない。ゲームディレクトリは `~/<ゲーム名>`。

3. **号機番号を確定**
   - **完成機は原則すべて 1号機（01）**（同型の2台目/3台目はクローン機で、そちらは `bash setup.sh` で 02/03 を付ける）。
   - ユーザが号機番号を言っていればそれを使う。
   - 言っていなければ「1号機（01）でよいですか？」と1回確認してから進める（重複防止のため勝手に確定しない）。

4. **ツール更新**: `git -C ~/exhibit-tools pull`

5. **ゲームを公開**: `bash ~/exhibit-tools/publish_game.sh --yes ~/<ゲーム名>`
   - 失敗したら**停止して報告**（再起動しない）。

6. **展示機に仕立てる**:
   `bash ~/exhibit-tools/setup.sh --game <ゲーム名> --instance <NN> --yes --no-reboot`
   - これで autostart 配線・hostname(`<ゲーム名>-NN`)/machine-id/SSH鍵 再生成・キオスク硬化・
     オーバーレイON までが済む（`--no-reboot` なのでまだ再起動しない）。
   - 失敗したら**停止して報告**（再起動しない）。

7. **結果を報告**: 実行後、ユーザに要約を伝える（機体名 `<ゲーム名>-NN`、公開URL、オーバーレイON、
   これから再起動する旨）。

8. **再起動**: 上記が全て成功していれば `sudo reboot`。

## 注意

- **root で実行しない**（`game` ユーザのまま。スクリプトが必要時に自分で sudo する）。
- **号機番号は絶対に勝手に決めない**（重複防止のためユーザに確認）。
- 途中で1つでも失敗したら、**その場で止めて報告**し、`sudo reboot` はしない。
- クローン機（claude 未導入）向けの対話セットアップは `bash setup.sh`（引数なし）。詳細は README.md。
