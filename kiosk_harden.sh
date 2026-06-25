#!/usr/bin/env bash
# ============================================================================
#  kiosk_harden.sh — 筐体セッションから「ゲーム上に出るダイアログ源」を停止する
# ----------------------------------------------------------------------------
#  目的:
#    ゲーム実行中に WiFi 接続先を尋ねるウィンドウ等が前面に出て、操作不能に
#    なる事象を、根本（出させない）で防ぐ。ただし上部パネル（スタートメニュー・
#    時計・音量など）とデスクトップは残し、現地でキーボード/マウス→GUI で
#    保守できる操作性を保つ。
#
#  方針（2026-06-25 再改訂・外科的最小化）:
#    パネル(wf-panel-pi)を丸ごと止めるのは「やりすぎ」。現地GUI保守ができなく
#    なるため。代わりに、ダイアログを出す/不要なウィジェットだけを設定から外す:
#      - connect  … RPi Connect（リモート接続のサインイン等）
#      - bluetooth… Bluetooth ペアリングダイアログ
#      - updater  … 「新しいアップデートがあります」通知
#    ★ netman（WiFi 接続先を選ぶアイコン）は **残す**。各地に分散設置したとき、
#      現地でキーボード/マウス→パネルのWiFiアイコンから接続先を選べる必要があるため
#      （当初は元凶として外したが、接続先選択UIまで消える副作用が大きく、残す方針へ）。
#    スタートメニュー(smenu)・時計・音量・電源・USB取り出し・WiFi(netman) は残す。
#    NetworkManager デーモンは常駐し保存接続を自律再接続する（psk-flags=0=平文システム
#    保存で対話不要）。netman は普段「表示/手動切替UI」役。
#    ※ もしゲーム中に WiFi ダイアログが前面に出る事象が再発したら、その時に改めて
#      対処する（netman を外す/ダイアログを抑止する等）。現状は接続先選択の操作性を優先。
#
#  仕組み:
#    パネル設定はユーザ ~/.config/wf-panel-pi/wf-panel-pi.ini がシステム既定
#    /etc/xdg/wf-panel-pi/wf-panel-pi.ini を上書きする。後者（全ウィジェットの
#    既定）を基に、上記ウィジェットを除いた版を前者へ書き出す。
#
#  旧版からの移行:
#    旧 kiosk_harden はパネル/デスクトップ自体を /etc/xdg/labwc/autostart で
#    無効化し、polkit エージェントをマスクしていた。本版はそれを取り消す
#    （.orig からの復元・マスク解除）ので、旧版適用済みの機体に上書き実行すれば
#    パネル/デスクトップが復活し、ウィジェット除去方式へ移行する。
#
#  特徴:
#    - 冪等（何度実行してもよい）。--revert で既定パネルへ戻す。
#    - root（sudo bash / freegame_setup から呼ばれる）でも一般ユーザでも動作する。
#      パネル設定の書込先は SUDO_USER（無ければ game）の home。
#    - 反映は次回 labwc セッション開始（再起動/再ログイン）から。稼働中に即反映
#      したい場合は `pkill -x wf-panel-pi`（lwrespawn が新設定で再起動する）。
#
#  使い方:
#    bash kiosk_harden.sh             # 一般ユーザで適用（/etc は sudo 昇格）
#    sudo bash kiosk_harden.sh        # root で適用（筐体ユーザの home を自動判定）
#    bash kiosk_harden.sh --revert    # 既定パネル（全ウィジェット）に戻す
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
SYS_PANEL=/etc/xdg/wf-panel-pi/wf-panel-pi.ini
USER_PANEL="$TARGET_HOME/.config/wf-panel-pi/wf-panel-pi.ini"
# 除去するパネルウィジェット。netman(WiFi接続UI)は接続先選択に要るので残す。
KILL_WIDGETS=(connect bluetooth updater)
# 旧版がマスクしていた polkit エージェント（本版では解除する）
OLD_MASK_AGENTS=(lxpolkit polkit-mate-authentication-agent-1)
MARK="kiosk_harden"

# ユーザ所有でファイルを作る（root 実行時も筐体ユーザ所有に揃える）
write_user_file() {  # $1=path  本文は stdin
  local path="$1" dir; dir="$(dirname "$path")"
  $SUDO mkdir -p "$dir"
  cat | $SUDO tee "$path" >/dev/null
  if [ "$(id -u)" = "0" ]; then
    local grp; grp="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"
    $SUDO chown "$TARGET_USER":"$grp" "$dir" "$path" 2>/dev/null || true
  fi
}

# widgets 行から KILL_WIDGETS を除き、連続/前後の spacing トークンを整理して返す
clean_widgets() {  # $1=元の widgets 値（空白区切り）
  local out=() prev="" tok drop
  for tok in $1; do
    drop=0
    for k in "${KILL_WIDGETS[@]}"; do [ "$tok" = "$k" ] && { drop=1; break; }; done
    [ "$drop" = 1 ] && continue
    # spacing* が連続したら 1 個に畳む
    case "$tok" in
      spacing*) [ "${prev#spacing}" != "$prev" ] && continue ;;
    esac
    out+=("$tok"); prev="$tok"
  done
  # 先頭/末尾の spacing トークンを削る
  while [ "${#out[@]}" -gt 0 ]; do case "${out[0]}" in spacing*) out=("${out[@]:1}");; *) break;; esac; done
  while [ "${#out[@]}" -gt 0 ]; do local last=$(( ${#out[@]} - 1 )); case "${out[$last]}" in spacing*) unset 'out[last]'; out=("${out[@]}");; *) break;; esac; done
  echo "${out[*]}"
}

restore_old_disables() {
  # 旧版が /etc/xdg/labwc/autostart でパネル/デスクトップを無効化していたら復元
  if [ -f "${SYS_AUTOSTART}.orig" ]; then
    if grep -qE "$MARK: disabled" "$SYS_AUTOSTART" 2>/dev/null; then
      $SUDO cp -a "${SYS_AUTOSTART}.orig" "$SYS_AUTOSTART"
      echo "  旧版の無効化を取り消し: $SYS_AUTOSTART を .orig から復元（パネル/デスクトップ復活）"
    fi
  fi
  # 旧版の polkit マスクを解除
  for a in "${OLD_MASK_AGENTS[@]}"; do
    f="$USER_AUTOSTART_DIR/$a.desktop"
    if [ -f "$f" ] && grep -q "$MARK" "$f" 2>/dev/null; then
      $SUDO rm -f "$f"; echo "  旧版マスク解除: $f"
    fi
  done
}

apply() {
  echo "== キオスク硬化: パネルは残し、ダイアログ源ウィジェットだけ除去（対象ユーザ: $TARGET_USER）=="

  # --- 0. 旧版（パネル丸ごと無効化）からの移行を先に処理 ---
  restore_old_disables

  # --- 1. パネル設定: KILL_WIDGETS を除いた版をユーザ設定に書き出す ---
  if [ ! -f "$SYS_PANEL" ]; then
    echo "  !! $SYS_PANEL が無いためパネル設定はスキップ。"
    return
  fi
  # 既存のユーザ設定が「我々のものでない」内容なら退避（初回のみ）
  if [ -f "$USER_PANEL" ] && ! grep -q "$MARK" "$USER_PANEL" 2>/dev/null && [ -s "$USER_PANEL" ] \
     && [ ! -f "${USER_PANEL}.preharden" ]; then
    $SUDO cp -a "$USER_PANEL" "${USER_PANEL}.preharden"
    echo "  既存ユーザ設定を退避: ${USER_PANEL}.preharden"
  fi

  local orig_right cleaned
  orig_right="$(grep -E '^[[:space:]]*widgets_right[[:space:]]*=' "$SYS_PANEL" | head -1 | cut -d= -f2-)"
  cleaned="$(clean_widgets "$orig_right")"

  # システム既定を1行ずつ写し、widgets_right だけ差し替え、先頭に MARK コメントを付す
  {
    echo "# $MARK: パネルは残しつつ WiFi/更新等のダイアログ源ウィジェットを除去した版"
    echo "# 除去ウィジェット: ${KILL_WIDGETS[*]}（NetworkManager 本体は常駐継続＝WiFiは切れない）"
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*widgets_right[[:space:]]*= ]]; then
        echo "widgets_right=$cleaned"
      else
        echo "$line"
      fi
    done < "$SYS_PANEL"
  } | write_user_file "$USER_PANEL"

  echo "  [パネル] $USER_PANEL を生成:"
  echo "        除去: ${KILL_WIDGETS[*]}"
  echo "        widgets_right=$cleaned"
  echo "== 完了。次回 labwc セッション開始（再起動/再ログイン）から有効。"
  echo "   稼働中に即反映: pkill -x wf-panel-pi  （lwrespawn が新設定で再起動）"
  echo "   元に戻す: bash $0 --revert"
}

revert() {
  echo "== キオスク硬化を元に戻します（既定パネルへ。対象ユーザ: $TARGET_USER）=="
  # 我々が作ったパネル設定を撤去（退避があれば復元、無ければ削除＝システム既定に戻る）
  if [ -f "$USER_PANEL" ] && grep -q "$MARK" "$USER_PANEL" 2>/dev/null; then
    if [ -f "${USER_PANEL}.preharden" ]; then
      $SUDO cp -a "${USER_PANEL}.preharden" "$USER_PANEL"
      $SUDO rm -f "${USER_PANEL}.preharden"
      echo "  復元: $USER_PANEL (.preharden から)"
    else
      $SUDO rm -f "$USER_PANEL"
      echo "  削除: $USER_PANEL（システム既定 $SYS_PANEL に戻る）"
    fi
  else
    echo "  我々のパネル設定は無し（変更なし）"
  fi
  # 旧版の無効化・マスクが残っていれば併せて解除
  restore_old_disables
  echo "== 完了。再起動/再ログイン（or pkill -x wf-panel-pi）で反映 =="
}

case "${1:-}" in
  --revert) revert ;;
  ""|--apply) apply ;;
  *) echo "使い方: bash $0 [--apply|--revert]"; exit 1 ;;
esac
