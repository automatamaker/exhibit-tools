#!/usr/bin/env bash
# ============================================================================
#  bootstrap.sh — クローン機のセットアップを1コマンドで開始する
# ----------------------------------------------------------------------------
#  exhibit-tools を用意（無ければ取得・有れば更新）してから setup.sh を起動する。
#  claude 未導入のクローン機で、貼り付け1回でセットアップに入るための入口。
#
#  使い方（クローン機のターミナルで1回）:
#    ● exhibit-tools が public の場合（推奨・最短）:
#        bash <(curl -fsSL https://raw.githubusercontent.com/automatamaker/exhibit-tools/master/bootstrap.sh)
#    ● private の場合（gh ログイン済みが前提）:
#        gh repo clone automatamaker/exhibit-tools ~/exhibit-tools && bash ~/exhibit-tools/bootstrap.sh
#
#  この後は setup.sh の対話（ゲームを番号で選ぶ→号機番号→最終確認）に従うだけ。
# ============================================================================
set -euo pipefail
ORG=automatamaker
DIR="$HOME/exhibit-tools"

[ "$(id -u)" = 0 ] && { echo "!! root では実行しないでください（筐体ユーザ game で）"; exit 1; }

# オーバーレイが ON だと書込みが tmpfs に消える（clone しても再起動で消滅）。先に OFF が必須。
OV="$(sudo raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
if [ "$OV" = 0 ]; then
  echo "!! オーバーレイが ON（読取専用）です。取得の前に OFF にして再起動してください:"
  echo "     sudo raspi-config nonint disable_overlayfs && sudo reboot"
  echo "   再起動後にもう一度この bootstrap を実行してください。"
  exit 1
fi

# exhibit-tools を用意
if [ -d "$DIR/.git" ]; then
  echo "[tools] 既存 exhibit-tools を更新"
  git -C "$DIR" pull --ff-only || echo "  (pull はスキップ。既存のまま続行)"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "[tools] gh で exhibit-tools を取得"
  gh repo clone "$ORG/exhibit-tools" "$DIR"
else
  echo "[tools] git で exhibit-tools を取得"
  git clone "https://github.com/$ORG/exhibit-tools.git" "$DIR"
fi

echo "[setup] セットアップを開始します"
exec bash "$DIR/setup.sh" "$@"
