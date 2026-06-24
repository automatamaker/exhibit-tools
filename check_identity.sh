#!/usr/bin/env bash
# ============================================================================
#  check_identity.sh — この機体の「固有であるべき値」を表示する（読み取り専用）
# ----------------------------------------------------------------------------
#  クローンで重複していないか確認するための診断。各機で実行して見比べる。
#  machine-id / SSH鍵フィンガープリント / hostname が他機と一致していたら、
#  freegame_setup.sh で再生成すべき。CPUシリアルと MAC は“ハード固有”なので
#  クローンでも必ず違う＝重複判定の基準に使える。
# ============================================================================
set -u
echo "==================== identity check ===================="
echo "hostname        : $(hostname)"
echo "machine-id      : $(cat /etc/machine-id 2>/dev/null)"
echo "dbus machine-id : $(cat /var/lib/dbus/machine-id 2>/dev/null || echo '(なし)')"
echo "--- SSH ホスト鍵フィンガープリント（重複していたらクローン由来） ---"
for k in /etc/ssh/ssh_host_*_key.pub; do
  [ -e "$k" ] && ssh-keygen -lf "$k" 2>/dev/null | awk '{print "  "$2"  "$4}'
done
echo "--- ハード固有値（クローンでも必ず異なる＝重複判定の基準） ---"
echo "CPU serial      : $(awk '/Serial/{print $3}' /proc/cpuinfo | tail -1)"
for n in /sys/class/net/*/address; do
  ifc=$(basename "$(dirname "$n")")
  [ "$ifc" = "lo" ] && continue
  echo "MAC ($ifc)      : $(cat "$n")"
done
echo "========================================================"
