#!/usr/bin/env bash
# ============================================================================
#  wifi_prefer_24g.sh — 指定SSIDのWiFi接続を2.4GHz(band=bg)に固定する
# ----------------------------------------------------------------------------
#  背景: 館内の "automaton" は同一SSIDを 2.4GHz と 5GHz の両方で吹いており、
#        放置すると遅い5GHzに掴んでしまう機体が頻発する。NetworkManagerの
#        接続に band=bg を設定して2.4GHzに固定する（game02で実績のある対策）。
#
#  やること: SSIDに指定文字列（既定 automaton）を含む保存済みWiFi接続すべてに
#            802-11-wireless.band=bg / channel=0 を設定する。冪等。
#            反映は再接続 or 次回起動から（setup.sh はこの後 reboot する）。
#
#  使い方:  bash wifi_prefer_24g.sh                 # 既定SSID(automaton)を2.4固定
#           bash wifi_prefer_24g.sh <SSID部分一致>  # 別SSIDを対象に
#           bash wifi_prefer_24g.sh --dry-run       # 変更せず対象だけ表示
#           SSID_MATCH=xxx bash wifi_prefer_24g.sh  # 環境変数でも指定可
#
#  注意: 2.4に固定するので、その場所で2.4が飛んでいない場合は繋がらなくなる。
#        「5Gが遅すぎて使い物にならない」前提の対策。
# ============================================================================
set -euo pipefail

DRY=0
SSID_MATCH="${SSID_MATCH:-automaton}"
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; -*) echo "!! 不明なオプション: $a"; exit 1 ;; *) SSID_MATCH="$a" ;; esac; done

command -v nmcli >/dev/null 2>&1 || { echo "  [wifi] nmcli が無いためスキップ"; exit 0; }
[ -n "$SSID_MATCH" ] || { echo "  [wifi] 対象SSIDが空のためスキップ"; exit 0; }

[ "$DRY" = 1 ] && echo "※ DRY-RUN: 変更せず対象の表示のみ"
echo "== WiFi 2.4GHz固定: SSIDに「$SSID_MATCH」を含む接続を band=bg に =="

found=0 changed=0
while IFS= read -r uuid; do
  [ -n "$uuid" ] || continue
  ssid="$(nmcli -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null || true)"
  [ -n "$ssid" ] || continue
  case "$ssid" in *"$SSID_MATCH"*) ;; *) continue ;; esac
  found=1
  name="$(nmcli -g connection.id connection show "$uuid" 2>/dev/null || true)"
  curband="$(nmcli -g 802-11-wireless.band connection show "$uuid" 2>/dev/null || true)"
  if [ "$curband" = "bg" ]; then
    echo "  |$name| (SSID=|$ssid|): 既に band=bg（変更なし）"
    continue
  fi
  echo "  |$name| (SSID=|$ssid|): band=${curband:-未設定} → bg に固定"
  if [ "$DRY" = 0 ]; then
    if sudo nmcli connection modify "$uuid" 802-11-wireless.band bg 802-11-wireless.channel 0 2>/dev/null; then
      changed=1
    else
      echo "    !! 変更失敗（$name）: 手動で 'sudo nmcli connection modify \"$name\" 802-11-wireless.band bg' を試してください"
    fi
  fi
done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1}')

if [ "$found" = 0 ]; then
  echo "  対象SSID（$SSID_MATCH）の保存済み接続なし → 何もしません（この機体はまだ未接続かも）"
elif [ "$DRY" = 0 ] && [ "$changed" = 1 ]; then
  echo "  反映: 次回起動（または 'sudo nmcli connection up <接続名>'）で2.4GHzに接続します"
fi
