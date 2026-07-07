#!/usr/bin/env bash
# ============================================================================
#  fix_double_launch.sh — ゲームの「二重起動」源を探して無効化する
# ----------------------------------------------------------------------------
#  症状: セットアップ後、ゲームの音は鳴る/入力は効くのに画面がアトラクトの
#        まま等。原因はゲームが2つ起動していること（片方が入力デバイスを専有）。
#
#  setup.sh は ~/.config/labwc/autostart を run_game.sh に書き換えるが、機体に
#  よってはゲームが別の場所からも起動される:
#    1. /etc/xdg/labwc/autostart（システム側 labwc autostart）
#    2. /etc/xdg/autostart/*.desktop（システム側 XDG autostart）
#    3. ~/.config/autostart/*.desktop（ユーザ側 XDG autostart）
#    4. systemd user サービス / crontab @reboot
#  本スクリプトはこれらを走査し、ゲーム起動らしき項目を無効化する（すべて
#  バックアップ/リネームで元に戻せる）。exhibit-tools の run_game.sh は温存。
#
#  使い方:  bash fix_double_launch.sh            # 通常（オーバーレイOFF必須）
#           bash fix_double_launch.sh --skip-overlay-check   # setup.sh 内部用
# ============================================================================
set -euo pipefail

SKIP_OV=0
for a in "$@"; do case "$a" in --skip-overlay-check) SKIP_OV=1 ;; *) echo "!! 不明なオプション: $a"; exit 1 ;; esac; done
[ "$(id -u)" = 0 ] && { echo "!! root では実行しないでください（内部で必要時に sudo します）"; exit 1; }

# ゲーム起動らしき行/Exec のパターン（exhibit-tools の run_game.sh は除外）
PAT='(start_[A-Za-z0-9_]+\.sh|play_[A-Za-z0-9_]+\.sh|run_[A-Za-z0-9_]+\.sh|[A-Za-z0-9_/]+/main\.py|python3? [^ ]*main\.py)'
EXCL='exhibit-tools/run_game\.sh'
MARK="exhibit-tools:double-launch-fix"
# テスト用に差し替え可
SYS_LABWC="${SYS_LABWC:-/etc/xdg/labwc/autostart}"
SYS_XDG_DIR="${SYS_XDG_DIR:-/etc/xdg/autostart}"
USR_XDG_DIR="${USR_XDG_DIR:-$HOME/.config/autostart}"
USR_LABWC="${USR_LABWC:-$HOME/.config/labwc/autostart}"

if [ "$SKIP_OV" = 0 ]; then
  OV="$(sudo raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
  if [ "$OV" = 0 ]; then
    echo "!! オーバーレイが ON です。修正が消えてしまうので先に OFF にして再起動:"
    echo "     sudo raspi-config nonint disable_overlayfs && sudo reboot"
    exit 1
  fi
fi

echo "== ゲーム二重起動源の走査 =="
FOUND=0

echo "--- 現在動いているゲームらしきプロセス（参考） ---"
pgrep -af "$PAT" 2>/dev/null | grep -Ev "$EXCL|pgrep" | sed 's/^/  /' || echo "  (なし)"

# --- 1. システム側 labwc autostart ---
if [ -f "$SYS_LABWC" ] && grep -E "$PAT" "$SYS_LABWC" 2>/dev/null | grep -Ev "^\s*#|$EXCL" >/dev/null; then
  echo "--- [1] $SYS_LABWC にゲーム起動行を発見 → コメントアウト ---"
  grep -E "$PAT" "$SYS_LABWC" | grep -Ev "^\s*#|$EXCL" | sed 's/^/  無効化: /'
  [ -f "${SYS_LABWC}.pre_dlfix" ] || sudo cp -a "$SYS_LABWC" "${SYS_LABWC}.pre_dlfix"
  awk -v pat="$PAT" -v excl="$EXCL" -v mark="$MARK" '
    $0 !~ /^[[:space:]]*#/ && $0 ~ pat && $0 !~ excl { print "# [" mark "] " $0; next }
    { print }' "$SYS_LABWC" | sudo tee "${SYS_LABWC}.tmp" >/dev/null
  sudo mv "${SYS_LABWC}.tmp" "$SYS_LABWC"
  FOUND=1
fi

# --- 2/3. XDG autostart（システム側・ユーザ側）の .desktop ---
for d in "$SYS_XDG_DIR" "$USR_XDG_DIR"; do
  [ -d "$d" ] || continue
  for f in "$d"/*.desktop; do
    [ -f "$f" ] || continue
    if grep -E "^(Exec|TryExec|Path)=" "$f" 2>/dev/null | grep -E "$PAT" | grep -Ev "$EXCL" >/dev/null; then
      echo "--- [2/3] XDG autostart にゲーム起動を発見 → 無効化（リネーム） ---"
      echo "  $f → $(basename "$f").disabled"
      sudo mv "$f" "$f.disabled"
      FOUND=1
    fi
  done
done

# --- 4a. systemd user サービス ---
if [ -d "$HOME/.config/systemd/user" ]; then
  for f in "$HOME"/.config/systemd/user/*.service; do
    [ -f "$f" ] || continue
    if grep -E "^ExecStart=" "$f" 2>/dev/null | grep -E "$PAT" | grep -Ev "$EXCL" >/dev/null; then
      u="$(basename "$f")"
      echo "--- [4] systemd user サービスにゲーム起動を発見 → 停止・無効化 ---"
      echo "  $u"
      systemctl --user disable --now "$u" 2>/dev/null || true
      FOUND=1
    fi
  done
fi

# --- 4b. crontab（自動編集はせず報告のみ） ---
if crontab -l 2>/dev/null | grep -Ev '^\s*#' | grep -E "$PAT" | grep -Ev "$EXCL" >/dev/null; then
  echo "--- [4] crontab にゲーム起動らしき行があります（手動確認が必要） ---"
  crontab -l | grep -Ev '^\s*#' | grep -E "$PAT" | sed 's/^/  /'
  echo "  → 'crontab -e' で該当行を削除してください"
  FOUND=1
fi

echo
echo "--- ユーザ labwc autostart（正しい唯一の起動元・確認用） ---"
sed 's/^/  | /' "$USR_LABWC" 2>/dev/null || echo "  (無し!? setup.sh を再実行してください)"
echo
if [ "$FOUND" = 1 ]; then
  echo "== 無効化しました。反映手順: =="
  echo "   sudo raspi-config nonint enable_overlayfs && sudo reboot"
  echo "   （戻す場合: ${SYS_LABWC}.pre_dlfix の復元 / *.desktop.disabled のリネーム戻し）"
else
  echo "== 二重起動源は見つかりませんでした。別原因の可能性 → この出力を報告してください =="
fi
