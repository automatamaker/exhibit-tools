#!/usr/bin/env bash
# ============================================================================
#  publish_game.sh — 完成したゲームを git リポジトリ化して公開する（各完成機で1回）
# ----------------------------------------------------------------------------
#  目的:
#    展示フリートの各ゲーム(8種)は「完成版が各完成機にあるが git に無い」状態。
#    これを github.com/automatamaker/<ゲーム名> として公開し、以後クローン機は
#    そこから pull できるようにする。あわせて exhibit-tools/games.conf に
#    「そのゲームの起動方法」を登録し、後段のセットアップが空振りしないようにする。
#
#  この1本がやること:
#    1. .gitignore を整備（ログ/__pycache__/.venv/実行時スコア等のゴミを除外）
#    2. requirements.txt を検出/整備（pygame/pymunk/numpy/pyserial 等の依存を記録）
#    3. games.conf に「<ゲーム名> = <ランチャ>」を登録（起動方法を今この場で確定）
#    4. git init → commit → github.com/automatamaker/<ゲーム名> を作成して push
#    5. 変更した games.conf を exhibit-tools に commit/push
#
#  使い方:
#    bash publish_game.sh --dry-run ~/earth_defender   # 何も書かず/pushせず内容だけ表示（推奨: 先にこれ）
#    bash publish_game.sh ~/earth_defender             # 本番（確認プロンプトあり）
#    bash publish_game.sh                              # カレントがゲームディレクトリなら自動判定
#
#  前提: gh (GitHub CLI) が automatamaker で認証済み。無ければ手動手順を案内する。
# ============================================================================
set -euo pipefail

# --- 設定（必要なら書き換え） ---------------------------------------------
ORG="automatamaker"            # GitHub の owner（org/user）
VISIBILITY="public"            # 公開範囲: public | private
                               #   クローン機に gh が無く最新を git 取得するため展開中は public。
                               #   全台の移植完了後に各repoを private へ戻してよい（既設機はローカル起動で影響なし）。
MARK_BEGIN="# >>> exhibit-tools publish_game.sh >>>"
MARK_END="# <<< exhibit-tools publish_game.sh <<<"

# import 名 -> pip パッケージ名 の対応（ゲームで使いそうな第三者ライブラリのみ）
declare -A PKG_MAP=(
  [pygame]=pygame [pymunk]=pymunk [numpy]=numpy [scipy]=scipy
  [serial]=pyserial [pyserial]=pyserial [PIL]=pillow [cv2]=opencv-python
  [requests]=requests [gpiozero]=gpiozero [RPi]=RPi.GPIO [evdev]=evdev
  [pyautogui]=pyautogui [pygame_gui]=pygame_gui [yaml]=pyyaml [dotenv]=python-dotenv
)

EXHIBIT_TOOLS="$(cd "$(dirname "$0")" && pwd)"
GAMES_CONF="$EXHIBIT_TOOLS/games.conf"

# --- 引数 -------------------------------------------------------------------
#   --dry-run : 非破壊で内容確認のみ
#   --yes/-y  : 確認プロンプトを全て自動承認（claude が automode で駆動する時用）
DRY=0; YES=0; GAME_DIR=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    -*) echo "!! 不明なオプション: $a"; exit 1 ;;
    *) GAME_DIR="$a" ;;
  esac
done
[ -n "$GAME_DIR" ] || GAME_DIR="$PWD"
GAME_DIR="$(cd "$GAME_DIR" 2>/dev/null && pwd)" || { echo "!! ディレクトリが見つかりません"; exit 1; }
GAME_NAME="$(basename "$GAME_DIR")"

say() { echo "$@"; }
[ "$DRY" = 1 ] && say "※ DRY-RUN: ファイル書込・git・push は一切行いません（内容の確認のみ）"

say "============================================================"
say " ゲーム公開: $GAME_NAME"
say "   ディレクトリ : $GAME_DIR"
say "   公開先       : github.com/$ORG/$GAME_NAME ($VISIBILITY)"
say "============================================================"

# ゲームらしさの軽い確認（main.py も *.sh も無ければ止める）
# 注: `ls main.py *.sh` は片方が無いだけで ls 全体が非ゼロ終了するため使わない。
if [ ! -f "$GAME_DIR/main.py" ] && ! ls "$GAME_DIR"/*.sh >/dev/null 2>&1; then
  say "!! $GAME_DIR に main.py も *.sh も見当たりません。ゲームディレクトリを間違えていませんか？"
  exit 1
fi
if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
  read -r -p "このディレクトリを $ORG/$GAME_NAME として公開します。よいですか? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { say "中止しました。"; exit 0; }
fi

# --- 1. .gitignore を整備（管理ブロックを冪等に差し替え） -------------------
say "[1/5] .gitignore を整備"
GITIGNORE_BODY="$(cat <<'EOF'
# Python
__pycache__/
*.py[cod]
*.egg-info/
.pytest_cache/
# venv（絶対パス入りで他機では動かない・容量大。依存は requirements.txt で運ぶ）
.venv/
venv/
env/
# ログ・デバッグ（※ serial_logger.py 等のソースは消さない。ログ出力だけ除外）
*.log
nohup.out
judge_debug_*
*_log.txt
key_input_log.txt
serial_logs/
serial_log*.txt
# 開発ローカル（各機のclaude設定。ゲーム実行には不要）
.claude/
# 実行時スコア/状態（各機ローカル。pull で上書きしないよう除外）
daily_high_score.json
high_score*.json
highscore*.json
scores.json
# 迷子の撮影データ（assets/ 配下は除外しない＝ルート直下のみ）
/IMG_*.jpg
/IMG_*.jpeg
# メンテ用フラグ / OS ゴミ
STOP
.DS_Store
Thumbs.db
EOF
)"
GI="$GAME_DIR/.gitignore"
NEW_GI="$(
  # 既存 .gitignore から旧管理ブロックを除いた行を残しつつ、末尾に新ブロックを付け直す
  if [ -f "$GI" ]; then awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b{skip=1} !skip{print} $0==e{skip=0}' "$GI"; fi
  printf '%s\n%s\n%s\n' "$MARK_BEGIN" "$GITIGNORE_BODY" "$MARK_END"
)"
if [ "$DRY" = 1 ]; then
  say "   --- .gitignore に入る管理ブロック ---"; printf '%s\n' "$GITIGNORE_BODY" | sed 's/^/     /'
else
  printf '%s\n' "$NEW_GI" > "$GI"; say "   $GI を更新"
fi

# --- 2. requirements.txt を検出/整備 --------------------------------------
say "[2/5] 依存(requirements.txt)を検出"
mapfile -t IMPORTS < <(grep -rhoE '^[[:space:]]*(import|from)[[:space:]]+[A-Za-z0-9_]+' "$GAME_DIR" --include='*.py' 2>/dev/null | awk '{print $2}' | sort -u)
DETECTED=()
for imp in "${IMPORTS[@]:-}"; do
  [ -n "${PKG_MAP[$imp]:-}" ] && DETECTED+=("${PKG_MAP[$imp]}")
done
# 重複除去
mapfile -t DETECTED < <(printf '%s\n' "${DETECTED[@]:-}" | grep -v '^$' | sort -u)
REQ="$GAME_DIR/requirements.txt"
EXISTING=()
[ -f "$REQ" ] && mapfile -t EXISTING < <(grep -vE '^\s*(#|$)' "$REQ" 2>/dev/null || true)
say "   検出した第三者ライブラリ: ${DETECTED[*]:-(なし)}"
[ -f "$REQ" ] && say "   既存 requirements.txt: ${EXISTING[*]:-(空)}"
# 既存にパッケージ名が含まれていない検出分だけ追記候補にする（バージョン指定は尊重）
TO_ADD=()
for p in "${DETECTED[@]:-}"; do
  [ -n "$p" ] || continue
  found=0
  for ex in "${EXISTING[@]:-}"; do
    ex_name="${ex%%[=<>~!\[ ]*}"; ex_name="${ex_name//[[:space:]]/}"
    [ "$ex_name" = "$p" ] && { found=1; break; }
  done
  [ "$found" = 0 ] && TO_ADD+=("$p")
done
if [ "${#TO_ADD[@]}" -gt 0 ]; then
  say "   requirements.txt に追記: ${TO_ADD[*]}"
  if [ "$DRY" = 0 ]; then printf '%s\n' "${TO_ADD[@]}" >> "$REQ"; fi
else
  say "   追記の必要なし（検出分は既に記載済み or 依存なし）"
fi
say "   ※ バージョン固定したい場合は後で requirements.txt を手編集してください"

# --- 3. 起動方法を games.conf に登録 --------------------------------------
say "[3/5] 起動方法を判定して games.conf に登録"
# ルート直下のランチャ候補（補助スクリプトは除外）
mapfile -t LAUNCHERS < <(cd "$GAME_DIR" && ls start_*.sh play_*.sh run_*.sh start.sh 2>/dev/null | grep -viE '^(copy_config|install|setup|build)' || true)
SPEC=""
if [ "${#LAUNCHERS[@]}" -eq 1 ]; then SPEC="${LAUNCHERS[0]}"
elif [ "${#LAUNCHERS[@]}" -gt 1 ]; then
  say "   複数のランチャ候補: ${LAUNCHERS[*]}"
  if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then read -r -p "   起動に使うスクリプト名を入力 > " SPEC; else SPEC="${LAUNCHERS[0]}"; say "   先頭 ${LAUNCHERS[0]} を採用（違う場合は games.conf を手直し）"; fi
elif [ -f "$GAME_DIR/main.py" ]; then SPEC="main.py"
fi
if [ -z "$SPEC" ]; then
  if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then read -r -p "   起動指定(例 main.py / play_x.sh)を入力 > " SPEC; else SPEC="main.py"; fi
fi
# 対話時のみ確認/上書き可（--yes は検出値をそのまま採用）
if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
  read -r -p "   起動指定を「$SPEC」で登録します。別の値なら入力、そのままなら Enter > " ov
  [ -n "$ov" ] && SPEC="$ov"
fi
say "   → games.conf: $GAME_NAME = $SPEC"
if [ "$DRY" = 0 ]; then
  # ヘッダが無ければ作る
  if [ ! -f "$GAMES_CONF" ]; then
    cat > "$GAMES_CONF" <<EOF
# exhibit-tools games.conf — 各ゲームの起動方法（publish_game.sh が各完成機で登録）
# 形式:  <ゲーム名(ディレクトリ名)> = <ランチャ>
#   *.sh を指定 … ~/<ゲーム名> で bash 実行する起動スクリプト
#   *.py を指定 … ~/<ゲーム名> で venv(あれば)/python3 実行するエントリ
EOF
  fi
  # 既存行を消して追記（冪等）
  tmp="$(mktemp)"; grep -vE "^[[:space:]]*$GAME_NAME[[:space:]]*=" "$GAMES_CONF" > "$tmp" || true
  printf '%s = %s\n' "$GAME_NAME" "$SPEC" >> "$tmp"; mv "$tmp" "$GAMES_CONF"
fi

# --- 4. git init → commit → repo作成 → push ------------------------------
say "[4/5] git 化して push"
cd "$GAME_DIR"
if [ "$DRY" = 1 ]; then
  # dry-run では既存の .git に一切触れない（init も rm もしない）
  say "   (dry-run) ルート直下の項目（.gitignore でログ/__pycache__/.venv 等は除外される見込み）:"
  find "$GAME_DIR" -maxdepth 1 -mindepth 1 ! -name '.git' -printf '     %f\n' 2>/dev/null | sort | head -40
  say "   ディレクトリ総容量(参考/除外前): $(du -sh "$GAME_DIR" 2>/dev/null | cut -f1)"
  [ -d "$GAME_DIR/.git" ] && say "   （このディレクトリは既に .git があります。本番では push 更新になります）"
else
  # git identity（未設定なら gh のアカウントでリポジトリローカルに設定）
  [ -d .git ] || git init -q -b main
  git config user.name  >/dev/null 2>&1 || git config user.name  "$ORG"
  git config user.email >/dev/null 2>&1 || git config user.email "$(gh api user --jq .login 2>/dev/null || echo $ORG)@users.noreply.github.com"
  # 秘密ファイルの混入ガード
  if git status --porcelain --untracked-files=all | awk '{print $2}' | grep -qiE '(^|/)(\.env|.*secret.*|.*token.*|id_rsa|.*\.pem)$'; then
    say "!! 秘密っぽいファイル(.env/token/secret/鍵)が含まれます。中止します。.gitignore で除外してから再実行してください:"
    git status --porcelain --untracked-files=all | awk '{print $2}' | grep -iE '(^|/)(\.env|.*secret.*|.*token.*|id_rsa|.*\.pem)$' | sed 's/^/     /'
    exit 1
  fi
  git add -A
  say "   commit 対象:"; git status --short | sed 's/^/     /' | head -40
  say "   追跡サイズ(概算): $(git ls-files -z | du -ch --files0-from=- 2>/dev/null | tail -1 | cut -f1 || echo '?')"
  if [ "$YES" = 0 ]; then
    read -r -p "   この内容で commit / push しますか? [y/N] " ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { say "中止しました（ローカルの .gitignore/requirements/games.conf 変更は残っています）。"; exit 0; }
  fi
  if ! git diff --cached --quiet; then git commit -q -m "Publish $GAME_NAME for exhibit fleet"; else say "   (commit 済み・変更なし)"; fi
  # リポジトリが既にあれば push、無ければ作成して push
  if gh repo view "$ORG/$GAME_NAME" >/dev/null 2>&1; then
    git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$ORG/$GAME_NAME.git"
    git push -u origin HEAD
  else
    gh repo create "$ORG/$GAME_NAME" "--$VISIBILITY" --source=. --remote=origin --push
  fi
  say "   → https://github.com/$ORG/$GAME_NAME 公開完了"
fi

# --- 5. games.conf を exhibit-tools に反映 --------------------------------
say "[5/5] games.conf を exhibit-tools に commit/push"
if [ "$DRY" = 1 ]; then
  say "   (dry-run) $GAMES_CONF に「$GAME_NAME = $SPEC」を追記し、exhibit-tools を push する予定"
else
  cd "$EXHIBIT_TOOLS"
  git config user.name  >/dev/null 2>&1 || git config user.name  "$ORG"
  git config user.email >/dev/null 2>&1 || git config user.email "$(gh api user --jq .login 2>/dev/null || echo $ORG)@users.noreply.github.com"
  if ! git diff --quiet -- games.conf 2>/dev/null || [ -n "$(git status --porcelain games.conf)" ]; then
    git add games.conf
    git commit -q -m "games.conf: $GAME_NAME = $SPEC を登録"
    ans=y
    [ "$YES" = 0 ] && read -r -p "   exhibit-tools を push しますか? [y/N] " ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      # 8台の完成機が順に games.conf を足すので、push前に取り込んで衝突を避ける
      git pull --rebase --autostash -q 2>/dev/null || say "   (自動pull不可。push が弾かれたら 'git -C $EXHIBIT_TOOLS pull --rebase' 後に再push)"
      git push -q && say "   exhibit-tools push 完了" || say "   !! push 失敗。'git -C $EXHIBIT_TOOLS pull --rebase && git push' を試してください"
    else say "   commit のみ（push は保留）。後で 'git -C $EXHIBIT_TOOLS push' してください"; fi
  else
    say "   games.conf に変更なし"
  fi
fi

say "============================================================"
say " 完了: $GAME_NAME"
[ "$DRY" = 1 ] && say " ※ これは DRY-RUN でした。問題なければ --dry-run を外して本番実行してください。"
say "============================================================"
