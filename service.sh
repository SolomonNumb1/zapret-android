#!/data/data/com.termux/files/usr/bin/bash
# service.sh — меню управления zapret (аналог service.bat из Flowseal)
# Сам находит стратегии из strategies/*.conf и оборачивает zapret.sh.
# Запуск:  bash service.sh

BASE=/data/local/tmp/zapret
CONF="$BASE/zapret.conf"
ZS="$BASE/zapret.sh"
SERVICE_D=/data/adb/service.d/10zapret.sh
STRATEGY=""

[ -f "$CONF" ] || { echo "Нет конфига $CONF. Сначала: bash install.sh"; exit 1; }
. "$CONF"
STRATEGY="${STRATEGY:-alt11}"

strategies() {
  ls "$BASE/strategies"/*.conf 2>/dev/null | sed 's#.*/##; s/\.conf$//' | sort
}

pick_strategy() {
  local list=($(strategies)) i=1
  [ "${#list[@]}" -eq 0 ] && { echo "Стратегии не найдены в $BASE/strategies/"; return 1; }
  echo "--- Доступные стратегии ---"
  for s in "${list[@]}"; do
    if [ "$s" = "$STRATEGY" ]; then printf "  %2d) %s  [текущая]\n" "$i" "$s"
    else printf "  %2d) %s\n" "$i" "$s"; fi
    i=$((i+1))
  done
  read -rp "Номер стратегии (Enter — отмена): " n || return 0
  [ -n "$n" ] || return 0
  if [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le "${#list[@]}" ]; then
    local s="${list[$((n-1))]}"
    su -c "sed -i 's/^STRATEGY=.*/STRATEGY=$s/' $CONF"
    STRATEGY="$s"
    echo "Стратегия: $s"
    echo "Перезапустить сейчас? (y/n)"
    read -r y || { echo "Пропускаю перезапуск"; return 0; }
    [ "$y" = "y" ] && do_restart
  else
    echo "Некорректный номер"
  fi
}

do_start()   { bash "$ZS" start; }
do_stop()    { bash "$ZS" stop; }
do_restart() { bash "$ZS" restart; }
do_status()  { bash "$ZS" status; }
do_test()    { bash "$ZS" test; }

autostart_toggle() {
  if su -c "[ -f $SERVICE_D ]"; then
    read -rp "Автозапуск включён. Выключить? (y/n): " y || return 0
    [ "$y" = "y" ] && { su -c "rm -f $SERVICE_D"; echo "Автозапуск выключен"; }
  else
    read -rp "Автозапуск выключен. Включить? (y/n): " y || return 0
    if [ "$y" = "y" ]; then
      su -c "cat > $SERVICE_D" <<'EOF'
#!/system/bin/sh
sleep 15
sh /data/local/tmp/zapret/zapret.sh start >/dev/null 2>&1 &
EOF
      su -c "chmod 755 $SERVICE_D"
      echo "Автозапуск включён (поднимется при загрузке через ~15 с)"
    fi
  fi
}

menu() {
  local running
  if su -c "pgrep -x nfqws" >/dev/null 2>&1; then running="запущен"
  else running="остановлен"; fi
  echo
  echo "==================== zapret ===================="
  echo " Стратегия : $STRATEGY"
  echo " nfqws     : $running"
  echo "-----------------------------------------------"
  echo " 1) Запустить"
  echo " 2) Остановить"
  echo " 3) Перезапустить"
  echo " 4) Статус"
  echo " 5) Проверить доступность (test)"
  echo " 6) Сменить стратегию"
  echo " 7) Автозапуск: вкл/выкл"
  echo " 8) Выход"
  echo "================================================"
}

while true; do
  menu
  read -rp "Выберите пункт: " c || exit 0
  case "$c" in
    1) do_start ;;
    2) do_stop ;;
    3) do_restart ;;
    4) do_status ;;
    5) do_test ;;
    6) pick_strategy ;;
    7) autostart_toggle ;;
    8) echo "Пока"; exit 0 ;;
    *) echo "Некорректный пункт" ;;
  esac
done
