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

# Создаёт user-списки (lists/*-user.txt), на которые ссылаются стратегии,
# если их ещё нет. Обновление базовых списков их не трогает.
ensure_user_lists() {
  local ul
  for ul in $(grep -hEo 'lists/[^ \"=]+-user\.txt' "$BASE/strategies"/*.conf 2>/dev/null | sort -u); do
    su -c "test -f '$BASE/$ul' || touch '$BASE/$ul'" 2>/dev/null
  done
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

GH_TAR="https://codeload.github.com/SolomonNumb1/zapret-android/tar.gz/main"
GH_ASSET="https://github.com/SolomonNumb1/zapret-android/releases/latest/download/nfqws-linux-arm64"

fetch_repo() {
  curl -sL --max-time 60 "$GH_TAR" | tar xzf - -C "$1" 2>/dev/null \
    && [ -f "$1/zapret-android-main/VERSION" ] \
    && echo "$1/zapret-android-main"
}

update_check() {
  echo "Проверяю обновления (GitHub)..."
  local d="$(mktemp -d)" src
  src="$(fetch_repo "$d")" || { rm -rf "$d"; echo "Нет связи с GitHub"; return 1; }
  local remote="$(tr -d '[:space:]' < "$src/VERSION")"
  local cur="$(tr -d '[:space:]' < "$BASE/VERSION")"
  rm -rf "$d"
  if [ -z "$remote" ] || [ "$remote" = "$cur" ]; then
    echo "Обновлений нет — всё актуально ($cur)"
    return 0
  fi
  echo "  Доступно обновление: $cur -> $remote"
  read -rp "Обновить сейчас? (y/n): " y || return 0
  [ "$y" = "y" ] && update_apply
}

update_apply() {
  echo "Загружаю свежую версию с GitHub..."
  local d="$(mktemp -d)" src t
  src="$(fetch_repo "$d")" || { rm -rf "$d"; echo "Ошибка загрузки"; return 1; }
  echo "Обновляю списки и стратегии..."
  su -c "cp -f $src/lists/* $BASE/lists/ && cp -f $src/strategies/*.conf $BASE/strategies/"
  ensure_user_lists
  echo "Обновляю скрипты (zapret.conf не трогаю)..."
  su -c "cp -f $src/zapret.sh $src/zapret-watch.sh $src/service.sh $src/VERSION $BASE/"
  echo "Обновляю nfqws..."
  t="$(mktemp)"
  if curl -sL --max-time 30 -o "$t" "$GH_ASSET" && [ -s "$t" ]; then
    su -c "cp -f '$t' '$BASE/nfqws' && chmod 755 '$BASE/nfqws'"
  fi
  rm -f "$t"
  su -c "chmod 755 $BASE/zapret.sh $BASE/zapret-watch.sh $BASE/service.sh"
  rm -rf "$d"
  echo "Обновлено. Перезапускаю..."
  do_restart
}

user_sites() {
  local a
  while true; do
    echo "--- Свои домены ---"
    echo "  1) Обойти DPI (list-general-user.txt)"
    echo "  2) Исключить из zapret (list-exclude-user.txt)"
    echo "  3) Назад"
    read -rp "Выбор: " a || return 0
    case "$a" in
      1) user_edit "$BASE/lists/list-general-user.txt" "обходить DPI" "$BASE/lists/list-general.txt" ;;
      2) user_edit "$BASE/lists/list-exclude-user.txt" "исключить из zapret" "$BASE/lists/list-exclude.txt" ;;
      3) return 0 ;;
    esac
  done
}

# user_edit <файл> <описание> <базовый_список_для_дедупликации>
user_edit() {
  local ul="$1" what="$2" base="$3" a x
  while true; do
    echo
    echo "--- Домены, которые $what ---"
    echo "  Файл: $ul"
    if [ -s "$ul" ]; then cat "$ul"; else echo "  (пусто)"; fi
    echo "  1) Добавить домен   2) Удалить домен   3) Назад"
    read -rp "Выбор: " a || return 0
    case "$a" in
      1)
        read -rp "Домен(ы) через пробел: " d || return 0
        for x in $d; do
          x="${x%/}"
          [ -n "$x" ] || continue
          if grep -qx "$x" "$ul" 2>/dev/null || grep -qx "$x" "$base" 2>/dev/null; then
            echo "  уже есть (пропускаю): $x"
          else
            su -c "echo '$x' >> '$ul'"
            echo "  добавлено: $x"
          fi
        done
        do_restart
        ;;
      2)
        read -rp "Домен для удаления: " d || return 0
        [ -n "$d" ] || return 0
        su -c "grep -vx '$d' '$ul' > '$ul.tmp' && mv '$ul.tmp' '$ul'"
        echo "  удалено: $d"
        do_restart
        ;;
      3) return 0 ;;
    esac
  done
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
  echo " 9) Мои домены"
  echo " 10) Выход"
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
    9) user_sites ;;
    10) echo "Пока"; exit 0 ;;
    *) echo "Некорректный пункт" ;;
  esac
done
