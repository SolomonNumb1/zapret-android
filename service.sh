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

GH_BASE="https://raw.githubusercontent.com/SolomonNumb1/zapret-android/main"
GH_ASSET="https://github.com/SolomonNumb1/zapret-android/releases/latest/download/nfqws-linux-arm64"

update_check() {
  echo "Проверяю обновления (GitHub)..."
  local t="$(mktemp)"
  curl -sL --max-time 10 -o "$t" "$GH_BASE/VERSION"
  if [ ! -s "$t" ]; then
    rm -f "$t"
    echo "Нет связи с GitHub"
    return 1
  fi
  local remote="$(tr -d '[:space:]' < "$t")" cur="$(tr -d '[:space:]' < "$BASE/VERSION")"
  rm -f "$t"
  if [ "$remote" = "$cur" ]; then
    echo "Обновлений нет — всё актуально ($cur)"
    return 0
  fi
  echo "  Доступно обновление: $cur -> $remote"
  read -rp "Обновить сейчас? (y/n): " y || return 0
  [ "$y" = "y" ] && update_apply
}

update_apply() {
  echo "Обновляю списки и стратегии..."
  local f n t
  for d in lists strategies; do
    for f in "$BASE/$d"/*; do
      n="$(basename "$f")"
      t="$(mktemp)"
      curl -sL --max-time 15 -o "$t" "$GH_BASE/$d/$n" && [ -s "$t" ] && su -c "cp -f '$t' '$f'"
      rm -f "$t"
    done
  done
  echo "Обновляю скрипты (zapret.conf не трогаю)..."
  for n in zapret.sh zapret-watch.sh service.sh VERSION; do
    t="$(mktemp)"
    curl -sL --max-time 15 -o "$t" "$GH_BASE/$n" && [ -s "$t" ] && su -c "cp -f '$t' '$BASE/$n'"
    rm -f "$t"
  done
  echo "Обновляю nfqws..."
  t="$(mktemp)"
  if curl -sL --max-time 30 -o "$t" "$GH_ASSET" && [ -s "$t" ]; then
    su -c "cp -f '$t' '$BASE/nfqws' && chmod 755 '$BASE/nfqws'"
  fi
  rm -f "$t"
  su -c "chmod 755 $BASE/zapret.sh $BASE/zapret-watch.sh $BASE/service.sh"
  echo "Обновлено. Перезапускаю..."
  do_restart
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
  echo " 8) Проверить обновления"
  echo " 9) Выход"
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
    8) update_check ;;
    9) echo "Пока"; exit 0 ;;
    *) echo "Некорректный пункт" ;;
  esac
done
