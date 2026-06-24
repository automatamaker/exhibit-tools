#!/usr/bin/env bash
# ============================================================================
#  kiosk_harden.sh — 筐体セッションから「ゲーム上に出るダイアログ源」を停止する
# ----------------------------------------------------------------------------
#  目的:
#    ゲーム実行中に WiFi 接続先を尋ねるウィンドウ等が前面に出て、キーボード/
#    マウスの無い筐体で操作不能になる事象を、根本（出させない）で防ぐ。
#
#  背景（調査結果）:
#    - WiFi 接続ダイアログの出所は RPi 標準パネル wf-panel-pi のネットワーク
#      プラグイン。NetworkManager デーモンは別に常駐し続けるので、パネルを
#      止めても WiFi 再接続は自律維持される（保存接続は psk-flags=0 = 平文
#      システム保存で対話不要）。パネルは「表示」役にすぎない。
#    - 副次源としてキーリング解錠(gcr-prompter)は chromium がシークレット要求
#      時のみ発生（筐体に chromium は無い）。念のため polkit 認証エージェントも
#      マスクする。
#    - labwc はシステム autostart(/etc/xdg/labwc/autostart) とユーザ autostart
#      (~/.config/labwc/autostart) の両方を実行する。パネルはシステム側から
#      起動されるため、ユーザ側だけでは止められない → システム側を無害化する。
#
#  この処理（ダイアログ源だけ外科的に停止。筐体必須は温存）:
#    1. /etc/xdg/labwc/autostart の wf-panel-pi(=WiFi UI源) と pcmanfm-pi
#       (=デスクトップ) をコメントアウト。kanshi(画面) と lxsession-xdg-autostart
#       (pwrkey=電源キー無効化 / autotouch=タッチ構成 等の必須を起動) は温存。
#    2. polkit 認証エージェント(lxpolkit, polkit-mate)を筐体ユーザの
#       ~/.config/autostart に Hidden=true でマスク。
#
#  特徴:
#    - 冪等（何度実行してもよい）。原本は .orig に退避し --revert で復元可能。
#    - root（sudo bash / freegame_setup から呼ばれる）でも一般ユーザでも動作する。
#      root 実行時のユーザ autostart 書込先は SUDO_USER（無ければ game）の home。
#    - 反映は次回 labwc セッション開始（再起動 or 再ログイン）から。
#
#  使い方:
#    bash kiosk_harden.sh             # 一般ユーザで適用（/etc は sudo 昇格）
#    sudo bash kiosk_harden.sh        # root で適用（筐体ユーザの home を自動判定）
#    bash kiosk_harden.sh --revert    # 元に戻す
# ============================================================================
set -euo pipefail

# --- 実行コンテキスト判定（root/一般ユーザ両対応） -------------------------
if [ "$(id -u)" = "0" ]; then
  SUDO=""                       # 既に root。/etc 編集に昇格不要
  TARGET_USER="${SUDO_USER:-game}"
else
  SUDO="sudo"                   # /etc 編集は sudo で昇格
  TARGET_USER="$(id -un)"
fi
[ "$TARGET_USER" = "root" ] && TARGET_USER="game"   # 筐体ユーザに寄せる
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || { echo "!! ユーザ $TARGET_USER のホームが見つかりません"; exit 1; }

SYS_AUTOSTART=/etc/xdg/labwc/autostart
USER_AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
MASK_AGENTS=(lxpolkit polkit-mate-authentication-agent-1)
MARK="kiosk_harden"

# ユーザ所有でファイルを作る（root 実行時も筐体ユーザ所有に揃える）
write_user_file() {  # $1=path  本文は stdin
  local path="$1" dir; dir="$(dirname "$path")"
  mkdir -p "$dir"
  cat > "$path"
  if [ "$(id -u)" = "0" ]; then
    chown "$TARGET_USER":"$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")" "$dir" "$path" 2>/dev/null || true
  fi
}

revert() {
  echo "== キオスク硬化を元に戻します（対象ユーザ: $TARGET_USER）=="
  if [ -f "${SYS_AUTOSTART}.orig" ]; then
    $SUDO cp -a "${SYS_AUTOSTART}.orig" "$SYS_AUTOSTART"
    echo "  復元: $SYS_AUTOSTART (.orig から)"
  else
    echo "  .orig が無いため $SYS_AUTOSTART は変更しません"
  fi
  for a in "${MASK_AGENTS[@]}"; do
    f="$USER_AUTOSTART_DIR/$a.desktop"
    if [ -f "$f" ] && grep -q "$MARK" "$f" 2>/dev/null; then
      rm -f "$f"; echo "  マスク解除: $f"
    fi
  done
  echo "== 完了。再起動 or 再ログインで元の構成に戻ります =="
}

apply() {
  echo "== キオスク硬化: ゲーム上に出るダイアログ源を停止します（対象ユーザ: $TARGET_USER）=="

  # --- 1. システム labwc autostart: パネル / デスクトップファイラ を無効化 ---
  if [ -f "$SYS_AUTOSTART" ]; then
    # 初回のみ原本を退避（以後はこの原本から毎回生成するので冪等）
    [ -f "${SYS_AUTOSTART}.orig" ] || $SUDO cp -a "$SYS_AUTOSTART" "${SYS_AUTOSTART}.orig"
    # wf-panel-pi(WiFi/ネットワークUI源) と pcmanfm-pi(デスクトップ) をコメントアウト
    $SUDO awk -v mark="$MARK" '
      /lwrespawn.*(wf-panel-pi|pcmanfm-pi)/ && $0 !~ /^[[:space:]]*#/ {
        print "#" $0 "   # " mark ": disabled (dialog source)"; next
      }
      { print }
    ' "${SYS_AUTOSTART}.orig" | $SUDO tee "$SYS_AUTOSTART" >/dev/null
    echo "  [1] $SYS_AUTOSTART を更新:"
    sed 's/^/        /' "$SYS_AUTOSTART"
  else
    echo "  [1] $SYS_AUTOSTART が無いためスキップ"
  fi

  # --- 2. polkit 認証エージェントを筐体ユーザ層でマスク ---------------------
  for a in "${MASK_AGENTS[@]}"; do
    if [ -f "/etc/xdg/autostart/$a.desktop" ]; then
      write_user_file "$USER_AUTOSTART_DIR/$a.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$a (disabled for kiosk by $MARK)
Hidden=true
X-$MARK=true
EOF
      echo "  [2] マスク: $a  ($USER_AUTOSTART_DIR/$a.desktop)"
    fi
  done

  echo "== 完了。次回 labwc セッション開始（再起動 or 再ログイン）から有効です =="
  echo "   元に戻す場合: bash $0 --revert"
}

case "${1:-}" in
  --revert) revert ;;
  ""|--apply) apply ;;
  *) echo "使い方: bash $0 [--apply|--revert]"; exit 1 ;;
esac
