# zapret-android

Запуск zapret (обход DPI) для YouTube и Discord на Android с root (KernelSU / Magisk) через Termux.

В отличие от VPN, трафик не шифруется и не перенаправляется на сторонний сервер: пакеты обрабатываются
локально (nfqws + iptables NFQUEUE), поэтому скорость и задержки не меняются.

Проект построен вокруг официального [zapret](https://github.com/bol-van/zapret) (nfqws v72.13) и
готовых стратегий [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube),
конвертированных из Windows-скриптов в конфиги nfqws для Linux.

---

## Содержание

- [Требования](#требования)
- [Установка](#установка)
- [Управление](#управление)
- [Конфигурация](#конфигурация)
- [Стратегии](#стратегии)
- [Как это работает](#как-это-работает)
- [Обновление стратегий (конвертер)](#обновление-стратегий-конвертер)
- [Решение проблем](#решение-проблем)
- [Ограничения](#ограничения)
- [Источники](#источники)

---

## Требования

- Android-устройство с root. Проверено на Xiaomi Redmi Note 14S, Android 16 (HyperOS 3.0), root KernelSU.
  Подойдёт и Magisk, главное чтобы работала команда `su`.
- [Termux](https://termux.dev) с пакетами `curl`, `tar` (обычно уже есть). Python нужен только для
  конвертера стратегий.
- Модуль ядра nfnetlink_queue и утилиты iptables/ip6tables (есть в любом Android).
- Доступ к GitHub (для скачивания nfqws и списков).

Проверить root:

```bash
su -c 'id'
```

Должно вернуть `uid=0`.

---

## Установка

1. Скопировать проект в Termux (например, в `~/zapret-android`).
2. Запустить установщик:

```bash
cd ~/zapret-android
bash install.sh
```

Что делает `install.sh`:

- копирует бинарники-пейлоады (`bin/`), списки доменов и IP (`lists/`), стратегии (`strategies/`)
  и скрипты в `/data/local/tmp/zapret`;
- если нет `nfqws` — скачивает официальный релиз `zapret-v72.13.tar.gz` и распаковывает из него
  `nfqws` для linux-arm64;
- настраивает права.

После установки файлы живут в `/data/local/tmp/zapret`. Повторный запуск `install.sh` обновит
скрипты и списки из репозитория, не трогая вашу конфигурацию.

---

## Управление

Все операции выполняются одной командой:

```bash
bash /data/local/tmp/zapret/zapret.sh start|stop|restart|status|test
```

| Команда    | Действие |
|------------|----------|
| `start`    | добавляет правила iptables, запускает nfqws и сторожевой процесс (watchdog) |
| `stop`     | останавливает watchdog и nfqws, снимает правила iptables |
| `restart`  | `stop` + `start` |
| `status`   | показывает, запущены ли nfqws и watchdog, сколько правил в iptables |
| `test`     | проверяет доступность youtube.com, discord.com и redirector.googlevideo.com |

### Автозапуск

Если устройство на KernelSU — zapret можно включить автоматически при загрузке через
boot-скрипты (выполняются от root, Termux не нужен):

```bash
su -c "cat > /data/adb/service.d/10zapret.sh" <<'EOF'
#!/system/bin/sh
sleep 15
sh /data/local/tmp/zapret/zapret.sh start >/dev/null 2>&1 &
EOF
su -c "chmod 755 /data/adb/service.d/10zapret.sh"
```

Скрипт ждёт 15 секунд (пока netd настроит сеть) и запускает zapret. Если правила iptables
позже сотрут — их восстановит сторожевой процесс.

Убрать автозапуск:

```bash
su -c "rm /data/adb/service.d/10zapret.sh"
```

Пример проверки после запуска:

```bash
bash /data/local/tmp/zapret/zapret.sh test
```

Ожидаемый результат:

```
www.youtube.com:  200
discord.com:      200
redirector.googlevideo.com: 404
```

Код 404 у redirector.googlevideo.com означает, что TLS-соединение прошло DPI (сам сервер отвечает
404 на корневой путь) — это нормальный признак успешного обхода.

---

## Конфигурация

Настройки в `/data/local/tmp/zapret/zapret.conf`:

```
# Стратегия обхода DPI. Имя файла из strategies/ без расширения .conf
STRATEGY=alt11

# Номер очереди NFQUEUE. Должен совпадать с --qnum= внутри strategies/*.conf
QUEUE=200

# TCP порты, которые направляются в очередь nfqws
TCP_PORTS=80,443,2053,2083,2087,2096,8443

# UDP порты, которые направляются в очередь nfqws
UDP_PORTS=443,19294-19344,50000-50100
```

`STRATEGY` можно менять в любой момент и перезапускать `zapret.sh restart`.

`QUEUE` менять не нужно: все сгенерированные конфиги используют 200. Если всё-таки измените —
придётся поменять `--qnum=` в каждом `strategies/*.conf` тоже.

Порты в `TCP_PORTS`/`UDP_PORTS` — это «широкий» набор: в очередь попадают все перечисленные
порты, а дальше уже nfqws решает, к какому профилю отнести соединение. Лишние порты не вредят.

---

## Стратегии

Стратегии — это наборы профилей десинхронизации DPI. Они лежат в `strategies/*.conf`
(генерируются конвертером из Flowseal, см. ниже).

| Файл               | Описание |
|--------------------|----------|
| `alt11.conf`       | базовая рекомендованная (проверена: YouTube, Discord, googlevideo) |
| `alt.conf` … `alt12.conf` | альтернативные варианты с разными seqovl/split-pos |
| `general.conf`     | базовая стратегия Flowseal |
| `exp.conf`         | экспериментальная |
| `fake-tls-auto*.conf` | варианты с подменой TLS-фейка (multidisorder, badseq) |
| `simple-fake*.conf` | упрощённые варианты |

Что внутри одного `.conf` (пример `alt11.conf`):

```
--qnum=200              ; очередь NFQUEUE
--bind-fix4             ; фикс выбора исходящего интерфейса для ipv4
--bind-fix6             ; то же для ipv6
--uid=1:3003            ; сброс привилегий (глюк медиатеки на Android, см. Ограничения)
--daemon                ; уйти в фоновый режим
--pidfile=nfqws.pid
--debug=@nfqws.log      ; лог отладки
--new                   ; разделитель профилей
--filter-udp=443
--hostlist=lists/list-general.txt
--dpi-desync=fake
--dpi-desync-repeats=11
--dpi-desync-fake-quic=bin/quic_initial_www_google_com.bin
...
--filter-tcp=443
--ipset=lists/ipset-all.txt
--ip-id=zero
--dpi-desync=fake,multisplit
...
```

Профили применяются по порядку; первый подходящий выигрывает.

Важно: конфиг передаётся nfqws единственным аргументом через `@`:
`nfqws @strategies/alt11.conf`. Поэтому все опции (включая `--qnum`, `--daemon`, `--pidfile`)
записаны прямо в файл, по одной на строку. Комментарии в конфиге nfqws не поддерживаются.

---

## Как это работает

Схема обработки трафика:

```
приложение -> iptables (mangle POSTROUTING) -> nfqws (очередь 200) -> DPI -> интернет
```

1. iptables направляет первые пакеты соединений на портах 80/443 (TCP) и 443/игровых (UDP)
   в очередь NFQUEUE 200 через `nfqws`.
2. `nfqws` определяет профиль соединения (по домену из списков `lists/*.txt`, по IP из
   `lists/ipset-all.txt`, по портам) и применяет десинхронизацию DPI:
   - `fake` — отправляет фейковый пакет (TLS ClientHello или QUIC Initial) с поддельным SNI;
   - `multisplit`/`disorder` — разбивает реальный ClientHello на части с перекрытием
     последовательностей, чтобы DPI не мог собрать SNI;
   - `fooling=ts`, `ip-id=zero` — маскировка под обычный стек TCP/IP.
3. DPI не видит целостного запроса к заблокированному домену и пропускает трафик.

### Почему нужен `ip-id=zero` и список `ipset-all.txt`

На некоторых DPI (в том числе ТСПУ) повторение ненулевых IP-идентификаторов у фейковых и реальных
пакетов триггерит блокировку именно диапазонов `googlevideo.com`. Опция `--ip-id=zero` обнуляет
IP-идентификатор всех генерируемых пакетов.

Кроме того, не все IP Google имеют подходящий обратный DNS (PTR), по которому nfqws определяет
домен для профилей с `--hostlist`. Поэтому важен IP-фильтр `--ipset`:

- `lists/ipset-all.txt` — 32132 записи IP/CIDR (список RKN/заблокированных подсетей Google и игр)
  из проекта Flowseal;
- `lists/ipset-exclude.txt` — исключения.

Внимание: `--ipset=` у nfqws — это обычный файл с IP/CIDR, ядру модуль ipset не нужен.

### Watchdog

Android (особенно HyperOS/MIUI) периодически пересобирает цепочку `mangle POSTROUTING` при
смене сети (мобильные данные, Wi-Fi, авиарежим) и молча стирает наши правила. Из-за этого zapret
может «отвалиться» сам по себе.

Чтобы это исправить, при `start` запускается фоновый сторожевой процесс `zapret-watch.sh`
(работает от root):

- каждые 15 секунд проверяет, на месте ли правила NFQUEUE, и при необходимости пере-добавляет их;
- проверяет, жив ли `nfqws`, и при необходимости перезапускает его.

Останавливается watchdog командой `stop` (маркер `watch.stop` + завершение процесса).

### Правила iptables

Добавляются в `mangle POSTROUTING` для IPv4 и IPv6:

```
-POSTROUTING ! -o lo -p tcp -m multiport --dports <TCP_PORTS>
 -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6
 -m mark ! --mark 0x40000000/0x40000000 -j NFQUEUE --queue-num 200 --queue-bypass
```

- `connbytes 1:6` — в очередь попадают только первые 6 пакетов соединения (экономия CPU);
- `mark ! 0x40000000` — не пере-отправлять в очередь пакеты, сгенерированные самим nfqws;
- `--queue-bypass` — если nfqws не запущен, трафик проходит без обработки (не блокируется).

---

## Обновление стратегий (конвертер)

Оригинальные стратегии Flowseal — это `.bat`-файлы для Windows (запускают `winws.exe`).
Проект содержит их в `strategies/bat/` и конвертер `tools/convert.py`, который превращает их в
конфиги nfqws для Linux/Android.

```bash
python3 tools/convert.py
```

Конвертер делает следующее:

- вырезает Windows-опции (`--wf-tcp`, `--wf-udp`);
- раскрывает переменные `%BIN%`/`%LISTS%` в относительные пути `bin/...` и `lists/...`;
- оставляет IP-фильтры (`--ipset=`, `--ipset-exclude=`), поскольку у nfqws это файловые списки;
- отбрасывает списки, которых нет в репозитории (user-списки, не скачиваются);
- отбрасывает игровые профили на `%GameFilterTCP%`/`%GameFilterUDP%` (зависят от игры);
- добавляет заголовок: `--qnum=200`, `--bind-fix4/6`, `--uid=1:3003`, `--daemon`,
  `--pidfile`, `--debug`.

Чтобы обновить стратегии из свежего репозитория Flowseal:

```bash
cd strategies/bat
# скачать новые general___*.bat в эту папку
cd ../..
python3 tools/convert.py
bash install.sh        # скопировать обновлённые конфиги на устройство
```

---

## Решение проблем

### Не работают YouTube/Discord

1. Проверить, что nfqws и watchdog запущены: `bash zapret.sh status`.
2. Проверить доступность: `bash zapret.sh test`.
3. Посмотреть лог `nfqws.log` в `/data/local/tmp/zapret/`.
4. Попробовать другую стратегию в `zapret.conf` (например, `alt3` или `general`).

### Правила пропадают сами по себе

Это делает Android при смене сети. Сторожевой процесс должен восстановить их за 15 секунд.
Проверьте, что watchdog активен: `bash zapret.sh status`.

### YouTube открывается, но видео не грузится

Видео идёт с `*.googlevideo.com`. Для его обхода нужны два условия:

- профиль с `--ipset=lists/ipset-all.txt` (он есть во всех сгенерированных конфигах);
- `--ip-id=zero` в профилях для google (есть в `alt11`).

Проверка: `bash zapret.sh test` — redirector.googlevideo.com должен вернуть 404, а не таймаут.

### yt-dlp пишет «Video unavailable»

Это блокировка на стороне YouTube (проверка клиента/аккаунта), а не DPI. Проверьте тем же
браузером на устройстве: если видео открывается в браузере, zapret работает, а yt-dlp упирается
в серверную проверку YouTube.

### Не хватает производительности на слабых устройствах

Стратегия `simple-fake` (и `simple-fake-alt`, `simple-fake-alt2`) использует меньше операций —
подойдёт для слабых телефонов.

### Медиатека/плееры «глючат» при включённом zapret

nfqws работает с пониженными привилегиями (`--uid=1:3003`). Если у вас наблюдаются проблемы
именно с воспроизведением медиа, можно убрать строку `--uid=1:3003` из конфигов стратегий
(тогда nfqws останется root-процессом).

---

## Ограничения

- Обход работает только на тех портах и доменах, которые описаны в профилях. Весь остальной
  трафик идёт как обычно.
- Тестировалось на nfqws v72.13 для linux-arm64. Бинарник собирается под конкретную архитектуру,
  для ARMv7 или x86 нужно скачивать свой.
- Списки IP (`ipset-all.txt`) и доменов время от времени нужно обновлять (см. конвертер).
- Разные операторы используют разные DPI. Стратегия, которая работает у одного, может не
  подойти другому — поэтому в репозитории 21 вариант.

---

## Источники и лицензия

- [bol-van/zapret](https://github.com/bol-van/zapret) — nfqws, официальная документация (GPL-3.0).
  Бинарник не распространяется в этом репозитории, а скачивается при установке.
- [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) — стратегии
  (`strategies/bat/*.bat`), списки и payload (MIT).
- Собственный код (install.sh, zapret.sh, zapret-watch.sh, service.sh, tools/convert.py)
  распространяется по MIT — см. `LICENSE`.
