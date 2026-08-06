#!/system/bin/sh
# zapret-watch.sh — сторожевой процесс (root).
# Запускается zapret.sh start в фоне.
# Каждые 15 секунд:
#   1) проверяет и восстанавливает iptables-правила NFQUEUE (Android netd их стирает)
#   2) проверяет, что nfqws жив, и при необходимости перезапускает
# Останавливается при появлении файла-маркера $BASE/watch.stop

BASE=/data/local/tmp/zapret
CONF="$BASE/zapret.conf"
MARK=0x40000000
STOPFILE="$BASE/watch.stop"

[ -f "$CONF" ] || exit 1
. "$CONF"
QNUM="${QUEUE:-200}"

rule_tcp() {
  echo "POSTROUTING ! -o lo -p tcp -m multiport --dports $TCP_PORTS -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 -m mark ! --mark $MARK/$MARK -j NFQUEUE --queue-num $QNUM --queue-bypass"
}

rule_udp() {
  local udp="$(echo "$UDP_PORTS" | tr '-' ':')"
  echo "POSTROUTING ! -o lo -p udp -m multiport --dports $udp -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 -m mark ! --mark $MARK/$MARK -j NFQUEUE --queue-num $QNUM --queue-bypass"
}

flush_q() {
  # Удаляем ВСЕ правила очереди $QNUM (сколько бы их ни накопилось),
  # затем заново добавляем ровно по одному tcp/udp на таблицу.
  local ipt="$1" line cmd
  while line="$($ipt -t mangle -S POSTROUTING 2>/dev/null | grep "NFQUEUE --queue-num $QNUM" | head -1)"; do
    [ -n "$line" ] || break
    cmd="$(echo "$line" | sed 's/^-A /-D /')"
    $ipt -t mangle $cmd 2>/dev/null
  done
}

ensure_rules() {
  flush_q iptables
  iptables -t mangle -I $(rule_tcp) 2>/dev/null
  iptables -t mangle -I $(rule_udp) 2>/dev/null
  if [ -x /system/bin/ip6tables ]; then
    flush_q ip6tables
    ip6tables -t mangle -I $(rule_tcp) 2>/dev/null
    ip6tables -t mangle -I $(rule_udp) 2>/dev/null
  fi
}

ensure_nfqws() {
  if ! pgrep -x nfqws >/dev/null 2>&1; then
    (cd "$BASE" && "$BASE/nfqws" @strategies/"$STRATEGY".conf >/dev/null 2>&1) &
  fi
}

rm -f "$STOPFILE"
while [ ! -f "$STOPFILE" ]; do
  ensure_rules
  ensure_nfqws
  sleep 15
done
rm -f "$STOPFILE"
