#!/usr/bin/env bash
# ============================================================================
#  freegame_setup.sh — クローンで重複した「固有値」を各機ごとに作り直す
# ----------------------------------------------------------------------------
#  無料ゲーム機（ESP32なし・コインなし・払い出し記録なし）用。前の機体を
#  クローンして作ったため hostname / machine-id / SSH鍵 が重複している状態を、
#  各機で1回実行して解消する。ゲーム本体や autostart には触らない。
#
#  使い方:
#    sudo bash freegame_setup.sh                 # ホスト名を CPUシリアルから自動生成
#    sudo bash freegame_setup.sh <ホスト名>      # ホスト名を明示（例 pinball-01）
#
#  実行後 `sudo reboot`。同一LANに複数つないでも衝突しなくなる。
# ============================================================================
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "!! root で実行してください: sudo bash $0 $*"; exit 1; }

# --- ホスト名を決定（引数なしならハード固有の CPUシリアル末尾から生成） -----
HOST="${1:-}"
if [ -z "$HOST" ]; then
  SER="$(awk '/Serial/{print $3}' /proc/cpuinfo | tail -1)"
  SUF="${SER: -6}"; SUF="${SUF:-$(date +%s 2>/dev/null || echo x)}"
  HOST="game-${SUF}"
fi
# ホスト名として無効な文字を除去（英数とハイフンのみ）
HOST="$(echo "$HOST" | tr -cd 'A-Za-z0-9-')"
[ -n "$HOST" ] || { echo "!! 有効なホスト名を決定できませんでした"; exit 1; }

OLD_HOST="$(hostname)"
echo "============================================================"
echo " 固有値の再生成:"
echo "   ホスト名     : $OLD_HOST -> $HOST"
echo "   machine-id   : 再生成"
echo "   SSHホスト鍵  : 再生成"
echo "============================================================"
read -r -p "実行しますか? [y/N] " ans
[ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "中止しました。"; exit 0; }

# --- 1. ホスト名 -----------------------------------------------------------
echo "[1/3] ホスト名を $HOST に設定"
hostnamectl set-hostname "$HOST"
if grep -qE '^\s*127\.0\.1\.1' /etc/hosts; then
  sed -i -E "s/^(\s*127\.0\.1\.1\s+).*/\1$HOST/" /etc/hosts
else
  echo -e "127.0.1.1\t$HOST" >> /etc/hosts
fi

# --- 2. machine-id ---------------------------------------------------------
echo "[2/3] machine-id を再生成"
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup >/dev/null
ln -sf /etc/machine-id /var/lib/dbus/machine-id
echo "      new: $(cat /etc/machine-id)"

# --- 3. SSH ホスト鍵 -------------------------------------------------------
echo "[3/3] SSH ホスト鍵を再生成"
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A >/dev/null
echo "      $(ls /etc/ssh/ssh_host_*_key 2>/dev/null | wc -l) 本 再生成"

echo "============================================================"
echo " 完了。再起動で反映:  sudo reboot"
echo " 確認:  bash $(dirname "$0")/check_identity.sh"
echo "============================================================"
