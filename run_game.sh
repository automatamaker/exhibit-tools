#!/usr/bin/env bash
# ============================================================================
#  run_game.sh <ゲーム名> — games.conf を見てそのゲームを起動する
# ----------------------------------------------------------------------------
#  展示機の ~/.config/labwc/autostart から `run_game.sh <ゲーム名> &` の形で
#  1回だけ呼ばれる想定。games.conf の「<ゲーム名> = <ランチャ>」を読み、
#  ~/<ゲーム名> に cd して起動する。
#    ランチャが *.sh … その起動スクリプトを bash 実行（スクリプト側が cd/venv/log を持つ）
#    ランチャが *.py … venv(あれば .venv/bin/python)優先・無ければ python3 で実行
#  メンテで止めたいとき: touch ~/<ゲーム名>/STOP （戻すとき rm）
# ============================================================================
set -euo pipefail

GAME="${1:-}"
[ -n "$GAME" ] || { echo "usage: run_game.sh <game_name>"; exit 1; }

TOOLS="$(cd "$(dirname "$0")" && pwd)"
CONF="$TOOLS/games.conf"
HOME_DIR="${HOME:-/home/$(id -un)}"
GAME_DIR="$HOME_DIR/$GAME"

[ -f "$CONF" ] || { echo "run_game: $CONF が無い"; exit 1; }
# games.conf から起動指定(spec)を取得（前後空白を除去）
SPEC="$(awk -F= -v g="$GAME" '
  { key=$1; gsub(/^[ \t]+|[ \t]+$/,"",key) }
  key==g { val=substr($0, index($0,"=")+1); gsub(/^[ \t]+|[ \t]+$/,"",val); print val; exit }
' "$CONF")"
[ -n "$SPEC" ] || { echo "run_game: '$GAME' が games.conf に登録されていません"; exit 1; }
[ -d "$GAME_DIR" ] || { echo "run_game: $GAME_DIR が存在しません"; exit 1; }

cd "$GAME_DIR"

# メンテ用 STOP フラグ
[ -f "$GAME_DIR/STOP" ] && { echo "run_game: STOP フラグにより起動を抑止しました"; exit 0; }

case "$SPEC" in
  *.sh)
    # 起動スクリプトが自前で cd/venv/ログを持つ想定。そのまま実行。
    exec bash "$GAME_DIR/$SPEC"
    ;;
  *)
    # python エントリ。venv があれば優先、無ければ system python3。
    if [ -x "$GAME_DIR/.venv/bin/python" ]; then PY="$GAME_DIR/.venv/bin/python"; else PY="python3"; fi
    exec >>"$GAME_DIR/${GAME}.log" 2>&1
    echo "=== run_game $GAME $(date) ($PY $SPEC) ==="
    exec "$PY" "$GAME_DIR/$SPEC"
    ;;
esac
