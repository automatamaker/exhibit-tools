#!/usr/bin/env bash
# ============================================================================
#  fix_double_launch.sh — 二重起動の後始末（我々が入れた run_game 配線を除去）
# ----------------------------------------------------------------------------
#  症状: セットアップ後、ゲームの音は鳴る/入力は効くのに画面がアトラクトのまま等。
#  真因: 機体は元々ゲームを自動起動する仕組み（多くは systemd の system サービス
#        例: /etc/systemd/system/<game>.service）を持っているのに、旧 setup.sh が
#        ~/.config/labwc/autostart に run_game.sh の2つ目の起動を足していたこと。
#
#  正しい対処 = 機体元来の起動を残し、我々が足した run_game 配線だけを消す。
#  本スクリプトは ~/.config/labwc/autostart から exhibit-tools/run_game.sh の行を
#  除去し、機体の本来の起動元を表示する（可逆：除去前にバックアップを作る）。
#
#  使い方:  bash fix_double_launch.sh          # オーバーレイOFF で実行
#           bash fix_double_launch.sh --skip-overlay-check
#  ※ 新しい setup.sh は既存起動を検出して配線しないので、通常はこの後始末は不要。
#    旧版で既にセットアップして二重起動になっている機体のためのツール。
# ============================================================================
set -euo pipefail

SKIP_OV=0
for a in "$@"; do case "$a" in --skip-overlay-check) SKIP_OV=1 ;; *) echo "!! 不明なオプション: $a"; exit 1 ;; esac; done
[ "$(id -u)" = 0 ] && { echo "!! root では実行しないでください（内部で必要時に sudo）"; exit 1; }

HOME_DIR="${HOME:-/home/$(id -un)}"
AUTOSTART="$HOME_DIR/.config/labwc/autostart"

if [ "$SKIP_OV" = 0 ]; then
  OV="$(sudo raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
  if [ "$OV" = 0 ]; then
    echo "!! オーバーレイが ON です。修正が消えるので先に OFF にして再起動:"
    echo "     sudo raspi-config nonint disable_overlayfs && sudo reboot"
    exit 1
  fi
fi

echo "== 二重起動の後始末: run_game 配線を除去 =="

echo "--- いま動いているゲームらしきプロセス ---"
ps -eo pid,args | grep -iE 'main\.py|play_.*\.sh|run_game' | grep -v grep | sed 's/^/  /' || echo "  (なし)"

echo "--- 機体本来のゲーム起動元（これは残す） ---"
found_src=0
# systemd サービス
for svc in $(sudo grep -rIlE 'main\.py|/home/game/[A-Za-z0-9_]+/' /etc/systemd/system /lib/systemd/system /etc/systemd/user "$HOME_DIR/.config/systemd/user" 2>/dev/null); do
  u="$(basename "$svc")"
  if systemctl is-enabled "$u" >/dev/null 2>&1; then echo "  systemd(system): $u [enabled]"; found_src=1; fi
  if systemctl --user is-enabled "$u" >/dev/null 2>&1; then echo "  systemd(user): $u [enabled]"; found_src=1; fi
done
# autostart / .desktop / lxsession（run_game 以外でゲームを起動している行）
for f in /etc/xdg/labwc/autostart /etc/xdg/autostart/*.desktop "$HOME_DIR/.config/autostart"/*.desktop \
         /etc/xdg/lxsession/*/autostart "$HOME_DIR/.config/lxsession"/*/autostart /etc/rc.local; do
  [ -f "$f" ] || continue
  if grep -vE 'exhibit-tools/run_game' "$f" 2>/dev/null | grep -qE 'main\.py|play_[A-Za-z0-9_]+\.sh|start_[A-Za-z0-9_]+\.sh'; then
    echo "  $f"; found_src=1
  fi
done
[ "$found_src" = 0 ] && echo "  (自動起動元が見つかりません。除去すると起動しなくなる可能性→中止します)"

# run_game 配線の除去
if [ -f "$AUTOSTART" ] && grep -q 'exhibit-tools/run_game.sh' "$AUTOSTART" 2>/dev/null; then
  if [ "$found_src" = 0 ]; then
    echo "== 本来の起動元が確認できないため、安全のため run_game を除去しません =="
    echo "   （この機体は run_game だけがゲーム起動元の可能性。手動確認してください）"
    exit 1
  fi
  cp -a "$AUTOSTART" "$AUTOSTART.pre_unwire.$(date +%Y%m%d-%H%M%S)"
  grep -v 'exhibit-tools/run_game.sh' "$AUTOSTART" > "$AUTOSTART.tmp" && mv "$AUTOSTART.tmp" "$AUTOSTART"
  echo "== 除去しました: $AUTOSTART から run_game 行を削除 =="
  echo "--- 除去後 ---"; sed 's/^/  | /' "$AUTOSTART"
  echo "== 反映: sudo raspi-config nonint enable_overlayfs && sudo reboot =="
else
  echo "== run_game 配線は見つかりません（この機体は既にクリーン）=="
fi
