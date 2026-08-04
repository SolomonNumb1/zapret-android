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

iptables_ensure() {
  local ipt="$1" rule="$2"
  iptables -t mangle -C $rule 2>/dev/null || iptables -t mangle -I $rule 2>/dev/null
}

ensure_rules() {
  iptables_ensure iptables "$(rule_tcp)"
  iptables_ensure iptables "$(rule_udp)"
  if [ -x /system/bin/ip6tables ]; then
    iptables_ensure ip6tables "$(rule_tcp)"
    iptables_ensure ip6tables "$(rule_udp)"
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
