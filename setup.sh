#!/usr/bin/env bash
# ============================================================================
#  setup.sh — 展示機セットアップ（ゲームと号機名を選ぶ→固有値再生成＋硬化＋
#             autostart配線→オーバーレイON→再起動）を1本で行う
# ----------------------------------------------------------------------------
#  対象: クローン機（および完成機）。筐体ユーザ(game)で実行する（root不可）。
#  やること:
#    1. games.conf からゲームを選ぶ／号機番号を入れて機体名 <game>-NN を決める
#    2. ~/<game> が無ければ github.com/automatamaker/<game> から clone（有れば pull 可）
#    3. 依存(pygame/pymunk 等)を確認。足りなければ venv を作って requirements を導入
#    4. ここで最終確認（1回）→ 以降は一気に:
#    5. ~/.config/labwc/autostart を run_game.sh <game> に配線（既存はバックアップ）
#    6. sudo freegame_setup.sh -y <host>（hostname/machine-id/SSH鍵 再生成＋キオスク硬化）
#    7. sudo raspi-config nonint enable_overlayfs（オーバーレイON）→ sudo reboot
#
#  使い方:
#    bash setup.sh              # 対話（本番）
#    bash setup.sh --dry-run    # 選択と生成内容の確認のみ（clone/固有値/overlay/rebootを行わない）
# ============================================================================
set -euo pipefail

# 引数:
#   --dry-run          選択と生成内容の確認のみ（破壊操作なし）
#   --game <名>        ゲームを指定してメニューを省略（claude が automode で駆動する時用）
#   --instance <NN>    号機番号を指定して質問を省略
#   --yes              確認プロンプトを全て自動承認
#   --no-reboot        最後の sudo reboot を行わない（overlay ON までで停止。claude が後で再起動）
DRY=0; YES=0; NO_REBOOT=0; GAME=""; NN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    --game) GAME="${2:-}"; shift ;;
    --instance) NN="${2:-}"; shift ;;
    *) echo "!! 不明なオプション: $1"; exit 1 ;;
  esac
  shift
done

[ "$(id -u)" = 0 ] && { echo "!! root では実行しないでください。筐体ユーザで: bash setup.sh （内部で必要時に sudo します）"; exit 1; }

TOOLS="$(cd "$(dirname "$0")" && pwd)"
CONF="${GAMES_CONF:-$TOOLS/games.conf}"      # テスト時は GAMES_CONF で差し替え可
ORG="automatamaker"
HOME_DIR="${HOME:-/home/$(id -un)}"

# 依存の import 名 -> pip パッケージ名
declare -A PKG_MAP=(
  [pygame]=pygame [pymunk]=pymunk [numpy]=numpy [scipy]=scipy
  [serial]=pyserial [PIL]=pillow [cv2]=opencv-python [requests]=requests
  [gpiozero]=gpiozero [RPi]=RPi.GPIO [evdev]=evdev [pyautogui]=pyautogui
  [pygame_gui]=pygame_gui [yaml]=pyyaml [dotenv]=python-dotenv
)

[ "$DRY" = 1 ] && echo "※ DRY-RUN: clone/依存導入/固有値再生成/overlay/reboot は行いません（選択と生成内容の確認のみ）"
[ -f "$CONF" ] || { echo "!! $CONF がありません"; exit 1; }

# --- 事前チェック: オーバーレイが ON だと書込めない（このスクリプトは書込みが必要） ---
if [ "$DRY" = 0 ]; then
  OV="$(sudo raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
  if [ "$OV" = 0 ]; then
    echo "!! オーバーレイが ON（読取専用）です。書込みできないので先に OFF にして再起動してください:"
    echo "     sudo raspi-config nonint disable_overlayfs && sudo reboot"
    echo "   再起動後にもう一度このセットアップを実行してください。"
    exit 1
  fi
fi

# --- 1. ゲーム選択 ---------------------------------------------------------
mapfile -t GAMES < <(grep -vE '^[[:space:]]*(#|$)' "$CONF" | awk -F= '{k=$1; gsub(/^[ \t]+|[ \t]+$/,"",k); if(k!="") print k}')
if [ "${#GAMES[@]}" -eq 0 ]; then
  echo "!! games.conf にゲームが登録されていません。先に各完成機で publish_game.sh を実行してください。"
  exit 1
fi
if [ -n "$GAME" ]; then
  # --game 指定: games.conf に在るか検証
  found=0; for g in "${GAMES[@]}"; do [ "$g" = "$GAME" ] && found=1; done
  [ "$found" = 1 ] || { echo "!! ゲーム '$GAME' は games.conf に登録されていません。登録済み: ${GAMES[*]}"; exit 1; }
  echo "ゲーム指定: $GAME"
else
  echo "============================================================"
  echo " この機体を何のゲームにしますか？"
  i=1; for g in "${GAMES[@]}"; do printf "   %2d) %s\n" "$i" "$g"; i=$((i+1)); done
  echo "============================================================"
  read -r -p "番号 > " n
  [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#GAMES[@]}" ] || { echo "!! 番号が不正です"; exit 1; }
  GAME="${GAMES[$((n-1))]}"
fi

# --- 2. 号機番号 → 機体名 <game>-NN --------------------------------------
PREFIX="$(printf '%s' "$GAME" | tr -d '_')"     # アンダースコアは hostname 不可なので除去
nn="$NN"
[ -n "$nn" ] || read -r -p "何号機ですか？ (例 01 / 02 / 03) > " nn
nn="$(printf '%s' "$nn" | tr -cd '0-9')"; [ -n "$nn" ] || nn=1
nn="$(printf '%02d' "$((10#$nn))")"
HOST="${PREFIX}-${nn}"

GAME_DIR="$HOME_DIR/$GAME"
REPO="https://github.com/$ORG/$GAME"

echo
echo "  ゲーム   : $GAME"
echo "  機体名   : $HOST"
echo "  ディレクトリ: $GAME_DIR $( [ -d "$GAME_DIR" ] && echo '(既存→pull可)' || echo '(無し→clone)')"
echo

# --- 3. ゲーム取得（clone/pull）は破壊的でないので確認前に実施 -------------
ensure_game() {
  if [ ! -d "$GAME_DIR" ]; then
    echo "[取得] $ORG/$GAME を取得"
    if [ "$DRY" = 1 ]; then echo "   (dry-run) clone は行いません"; return; fi
    # private repo でも取れるよう gh を優先。無ければ git https。
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      gh repo clone "$ORG/$GAME" "$GAME_DIR" -- -q || { echo "!! clone 失敗（完成機で publish_game.sh 済みか確認）"; exit 1; }
    else
      git clone -q "$REPO" "$GAME_DIR" || { echo "!! clone 失敗（private repo は gh ログインが必要。完成機で publish 済みか・gh auth を確認）"; exit 1; }
    fi
  else
    if [ "$DRY" = 1 ]; then echo "   (dry-run) 既存ディレクトリ。pull 確認は本番のみ"
    elif [ "$YES" = 1 ]; then echo "[取得] $GAME_DIR は既存。そのまま使用（--yes のため pull しない）"
    else
      read -r -p "[取得] $GAME_DIR は既存。最新に git pull しますか? [y/N] " a
      if [ "$a" = "y" ] || [ "$a" = "Y" ]; then git -C "$GAME_DIR" pull --ff-only || echo "   (pull はスキップ/失敗。既存のまま続行)"; fi
    fi
  fi
}
ensure_game

# --- 4. 依存チェック（不足なら venv を作って導入） ------------------------
dep_check() {
  [ -d "$GAME_DIR" ] || { echo "[依存] $GAME_DIR が無いのでスキップ"; return; }
  local PY; if [ -x "$GAME_DIR/.venv/bin/python" ]; then PY="$GAME_DIR/.venv/bin/python"; else PY="python3"; fi
  mapfile -t IMPS < <(grep -rhoE '^[[:space:]]*(import|from)[[:space:]]+[A-Za-z0-9_]+' "$GAME_DIR" --include='*.py' 2>/dev/null | awk '{print $2}' | sort -u)
  local missing=() imp
  for imp in "${IMPS[@]:-}"; do
    [ -n "${PKG_MAP[$imp]:-}" ] || continue
    "$PY" -c "import $imp" >/dev/null 2>&1 || missing+=("${PKG_MAP[$imp]}")
  done
  mapfile -t missing < <(printf '%s\n' "${missing[@]:-}" | grep -v '^$' | sort -u)
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "[依存] OK（必要な第三者ライブラリは揃っています: $PY）"
    return
  fi
  echo "[依存] 不足: ${missing[*]}"
  if [ "$DRY" = 1 ]; then echo "   (dry-run) 本番では venv を作って導入します"; return; fi
  if [ "$YES" = 0 ]; then
    read -r -p "   $GAME_DIR/.venv を作成して導入しますか? [Y/n] " a
    if [ "$a" = "n" ] || [ "$a" = "N" ]; then echo "   スキップ（起動しない可能性あり。手動導入してください）"; return; fi
  fi
  python3 -m venv "$GAME_DIR/.venv"
  # pygame 等は system-site があると衝突しにくいが、確実性優先で venv 単独に入れる
  if [ -f "$GAME_DIR/requirements.txt" ]; then
    "$GAME_DIR/.venv/bin/pip" install -r "$GAME_DIR/requirements.txt"
  else
    "$GAME_DIR/.venv/bin/pip" install "${missing[@]}"
  fi
  echo "   導入完了（run_game.sh は .venv を自動優先します）"
}
dep_check

# --- autostart に書く内容（プレビュー用に生成） ---------------------------
AUTOSTART="$HOME_DIR/.config/labwc/autostart"
NEW_AUTOSTART="$(printf 'fcitx5 -d &\n%s/run_game.sh %s &\n' "$TOOLS" "$GAME")"

# --- 5〜7 をまとめて最終確認（1回） --------------------------------------
echo
echo "============================================================"
echo " ここから下は機体を書き換えます（この後 再起動します）:"
echo "   autostart 配線 : $AUTOSTART を↓に置換（既存はバックアップ）"
printf '%s\n' "$NEW_AUTOSTART" | sed 's/^/       | /'
echo "   固有値再生成   : hostname=$HOST, machine-id, SSHホスト鍵（＋キオスク硬化）"
echo "   オーバーレイ   : ON（sudo raspi-config nonint enable_overlayfs）"
echo "   最後に         : $( [ "$NO_REBOOT" = 1 ] && echo '（--no-reboot: 再起動は保留）' || echo 'sudo reboot' )"
echo "============================================================"
if [ "$DRY" = 1 ]; then
  echo "※ DRY-RUN 終了。実際の書き換え/再起動は行っていません。"
  exit 0
fi
if [ "$YES" = 0 ]; then
  read -r -p "この内容で実行し、再起動しますか? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "中止しました（clone/venv は残っています）。"; exit 0; }
fi

# --- 5. autostart 配線 -----------------------------------------------------
echo "[配線] $AUTOSTART"
mkdir -p "$(dirname "$AUTOSTART")"
[ -f "$AUTOSTART" ] && cp -a "$AUTOSTART" "$AUTOSTART.bak.$(date +%Y%m%d-%H%M%S)"
printf '%s\n' "$NEW_AUTOSTART" > "$AUTOSTART"

# --- 6. 固有値再生成＋キオスク硬化 ----------------------------------------
echo "[固有値] sudo freegame_setup.sh -y $HOST"
sudo bash "$TOOLS/freegame_setup.sh" -y "$HOST"

# --- 7. オーバーレイ ON → 再起動 -----------------------------------------
echo "[overlay] オーバーレイを有効化"
sudo raspi-config nonint enable_overlayfs
if [ "$NO_REBOOT" = 1 ]; then
  echo "[完了] --no-reboot のため再起動しません。反映するには: sudo reboot"
else
  echo "[reboot] 再起動します..."
  sudo reboot
fi
