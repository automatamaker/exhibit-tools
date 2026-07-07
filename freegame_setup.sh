#!/usr/bin/env bash
# ============================================================================
#  freegame_setup.sh — クローンで重複した「固有値」を各機ごとに作り直す
# ----------------------------------------------------------------------------
#  無料ゲーム機（ESP32なし・コインなし・払い出し記録なし）用。前の機体を
#  クローンして作ったため hostname / machine-id / SSH鍵 が重複している状態を、
#  各機で1回実行して解消する。ゲーム本体や autostart（ゲーム選択）には触らない。
#  あわせてキオスク硬化（kiosk_harden.sh）を実行し、ゲーム上に WiFi/認証ダイアログ
#  が出る原因をパネル設定から除く（パネル本体・スタートメニュー・WiFiアイコンは残すので
#  現地GUI保守・WiFi接続先選択は可能。除去するのは connect/bluetooth/updater のみ）。
#
#  使い方:
#    sudo bash freegame_setup.sh                 # ホスト名を CPUシリアルから自動生成
#    sudo bash freegame_setup.sh <ホスト名>      # ホスト名を明示（例 pinball-01）
#
#  実行後 `sudo reboot`。同一LANに複数つないでも衝突せず、ダイアログも出なくなる。
# ============================================================================
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "!! root で実行してください: sudo bash $0 $*"; exit 1; }

# --- 引数解釈: ホスト名 と -y(確認省略。setup.sh から呼ばれる時用) --------
ASSUME_YES="${ASSUME_YES:-0}"
HOST=""
for a in "$@"; do
  case "$a" in
    -y|--yes) ASSUME_YES=1 ;;
    -*) echo "!! 不明なオプション: $a"; exit 1 ;;
    *) HOST="$a" ;;
  esac
done
# --- ホスト名を決定（未指定ならハード固有の CPUシリアル末尾から生成） -----
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
echo "   キオスク硬化 : ダイアログ源ウィジェットを除去（パネル本体は残す）"
echo "============================================================"
if [ "$ASSUME_YES" = 1 ]; then
  echo "（-y 指定のため確認を省略して実行します）"
else
  read -r -p "実行しますか? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "中止しました。"; exit 0; }
fi

# --- 1. ホスト名 -----------------------------------------------------------
echo "[1/4] ホスト名を $HOST に設定"
hostnamectl set-hostname "$HOST"
if grep -qE '^\s*127\.0\.1\.1' /etc/hosts; then
  sed -i -E "s/^(\s*127\.0\.1\.1\s+).*/\1$HOST/" /etc/hosts
else
  echo -e "127.0.1.1\t$HOST" >> /etc/hosts
fi
# cloud-init 対策: 一部の機体は cloud-init が毎起動で /etc/hostname を元(game02等)へ
# 書き戻すため、hostnamectl の変更が定着しない。preserve_hostname: true で無効化する。
# cloud-init が無い機体では未使用のファイルが1つ増えるだけで無害。
if [ -d /etc/cloud ]; then
  echo "      cloud-init のホスト名上書きを無効化（preserve_hostname: true）"
  printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
  if grep -q '^preserve_hostname:' /etc/cloud/cloud.cfg 2>/dev/null; then
    sed -i 's/^preserve_hostname:.*/preserve_hostname: true/' /etc/cloud/cloud.cfg
  fi
fi

# --- 2. machine-id ---------------------------------------------------------
echo "[2/4] machine-id を再生成"
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup >/dev/null
ln -sf /etc/machine-id /var/lib/dbus/machine-id
echo "      new: $(cat /etc/machine-id)"

# --- 3. SSH ホスト鍵 -------------------------------------------------------
echo "[3/4] SSH ホスト鍵を再生成"
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A >/dev/null
echo "      $(ls /etc/ssh/ssh_host_*_key 2>/dev/null | wc -l) 本 再生成"

# --- 4. キオスク硬化（ダイアログ源の停止） ---------------------------------
echo "[4/4] キオスク硬化（パネルは残し WiFi/更新等のダイアログ源ウィジェットを除去）"
HARDEN="$(dirname "$0")/kiosk_harden.sh"
if [ -f "$HARDEN" ]; then
  # root のまま呼ぶ。kiosk_harden 側が SUDO_USER(=実行者) の home を対象にする。
  bash "$HARDEN" --apply | sed 's/^/      /'
else
  echo "      !! $HARDEN が見つかりません。キオスク硬化はスキップ。"
fi

echo "============================================================"
echo " 完了。再起動で反映:  sudo reboot"
echo " 確認:  bash $(dirname "$0")/check_identity.sh"
echo "============================================================"
