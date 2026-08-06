#!/system/bin/sh
# zapret.sh — управление zapret (nfqws + iptables NFQUEUE) на Android с root
# Использование:  bash zapret.sh start|stop|restart|status|test
# Запускается из Termux обычным пользователем; привилегии получаются через su.

BASE=/data/local/tmp/zapret
CONF="$BASE/zapret.conf"
MARK=0x40000000

[ -f "$CONF" ] || { echo "Конфиг не найден: $CONF"; echo "Сначала запустите install.sh"; exit 1; }
. "$CONF"
QNUM="${QUEUE:-200}"

rule_tcp() {
  echo "POSTROUTING ! -o lo -p tcp -m multiport --dports $TCP_PORTS -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 -m mark ! --mark $MARK/$MARK -j NFQUEUE --queue-num $QNUM --queue-bypass"
}

rule_udp() {
  local udp="$(echo "$UDP_PORTS" | tr '-' ':')"
  echo "POSTROUTING ! -o lo -p udp -m multiport --dports $udp -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 -m mark ! --mark $MARK/$MARK -j NFQUEUE --queue-num $QNUM --queue-bypass"
}

iptables_add() {
  local ipt="$1" rule="$2"
  su -c "$ipt -t mangle -C $rule" 2>/dev/null || su -c "$ipt -t mangle -I $rule"
}

iptables_del() {
  local ipt="$1" rule="$2"
  su -c "$ipt -t mangle -D $rule" 2>/dev/null
}

flush_q() {
  # Удаляем ВСЕ правила очереди $QNUM (сколько бы их ни накопилось),
  # затем заново добавляем ровно по одному tcp/udp на таблицу.
  local ipt="$1" line cmd
  while line="$($ipt -t mangle -S POSTROUTING 2>/dev/null | grep "NFQUEUE --queue-num $QNUM" | head -1)"; do
    [ -n "$line" ] || break
    cmd="$(echo "$line" | sed 's/^-A /-D /')"
    su -c "$ipt -t mangle $cmd" 2>/dev/null
  done
}

add_rules() {
  flush_q iptables
  iptables_add iptables "$(rule_tcp)"
  iptables_add iptables "$(rule_udp)"
  if [ -x /system/bin/ip6tables ]; then
    flush_q ip6tables
    iptables_add ip6tables "$(rule_tcp)"
    iptables_add ip6tables "$(rule_udp)"
  fi
}

del_rules() {
  flush_q iptables
  if [ -x /system/bin/ip6tables ]; then
    flush_q ip6tables
  fi
}

kill_nfqws() {
  su -c "pkill -x nfqws" 2>/dev/null
  sleep 1
}

start_watch() {
  su -c "rm -f $BASE/watch.stop; setsid sh $BASE/zapret-watch.sh >/dev/null 2>&1 &" 2>/dev/null
}

stop_watch() {
  su -c "touch $BASE/watch.stop; pkill -f '[z]apret-watch.sh'" 2>/dev/null
  local n=0
  while [ "$n" -lt 5 ]; do
    su -c "pgrep -f '[z]apret-watch.sh'" >/dev/null 2>&1 || return 0
    sleep 1
    n=$((n+1))
  done
}

start() {
  kill_nfqws
  stop_watch
  add_rules
  su -c "sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1" 2>/dev/null
  su -c "cd $BASE && $BASE/nfqws @strategies/$STRATEGY.conf"
  sleep 2
  start_watch
  echo "nfqws запущен со стратегией $STRATEGY (сторож активен)"
  status
}

stop() {
  stop_watch
  del_rules
  kill_nfqws
  echo "zapret остановлен"
}

status() {
  echo "=== nfqws ==="
  su -c "pgrep -x nfqws" 2>/dev/null && su -c "ps -p \$(pgrep -x nfqws) -o args=" 2>/dev/null || echo "nfqws не запущен"
  echo "=== watchdog ==="
  su -c "pgrep -f '[z]apret-watch.sh'" >/dev/null 2>&1 && echo "активен" || echo "не запущен"
  echo "=== правила iptables (NFQUEUE $QNUM) ==="
  su -c "iptables -t mangle -S POSTROUTING" 2>/dev/null | grep -c NFQUEUE | { read n; echo "v4 правил: $n"; }
  if [ -x /system/bin/ip6tables ]; then
    su -c "ip6tables -t mangle -S POSTROUTING" 2>/dev/null | grep -c NFQUEUE | { read n; echo "v6 правил: $n"; }
  fi
}

test_conn() {
  echo "=== проверка доступности ==="
  echo "www.youtube.com:  $(curl -s -o /dev/null -w '%{http_code} %{time_total}s' -m 8 https://www.youtube.com 2>/dev/null || echo 'FAIL')"
  echo "discord.com:      $(curl -s -o /dev/null -w '%{http_code} %{time_total}s' -m 8 https://discord.com 2>/dev/null || echo 'FAIL')"
  echo "redirector.googlevideo.com: $(curl -s -o /dev/null -w '%{http_code} %{time_total}s' -m 8 https://redirector.googlevideo.com 2>/dev/null || echo 'FAIL')"
}

case "$1" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  test)    test_conn ;;
  *)       echo "Использование: bash zapret.sh start|stop|restart|status|test"; exit 1 ;;
esac
