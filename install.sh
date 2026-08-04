#!/system/bin/sh
# install.sh — копирует файлы zapret-android в /data/local/tmp/zapret,
# при необходимости скачивает nfqws и готовит систему к запуску.
# Запускать из Termux:  bash install.sh
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/data/local/tmp/zapret
VER=v72.13
NFQWS_URL="https://github.com/bol-van/zapret/releases/download/$VER/zapret-$VER.tar.gz"

echo "==> Копирую файлы в $DEST"
su -c "mkdir -p $DEST/bin $DEST/lists $DEST/strategies"
su -c "cp -f $SRC/bin/* $DEST/bin/"
su -c "cp -f $SRC/lists/* $DEST/lists/"
su -c "cp -f $SRC/strategies/*.conf $DEST/strategies/"
su -c "cp -f $SRC/zapret.conf $SRC/zapret.sh $SRC/zapret-watch.sh $SRC/service.sh $DEST/"
su -c "chmod 755 $DEST/zapret.sh $DEST/zapret-watch.sh $DEST/service.sh"
su -c "chmod 644 $DEST/bin/* $DEST/lists/* $DEST/strategies/* $DEST/zapret.conf"

if [ ! -x "$DEST/nfqws" ]; then
  echo "==> Скачиваю nfqws $VER (linux-arm64)..."
  TMP="$(mktemp -d)"
  cd "$TMP"
  curl -sL -o z.tgz "$NFQWS_URL"
  tar xzf z.tgz
  NFQWS_BIN="$(find "$TMP" -type f -name nfqws -path '*linux-arm64*' | head -1)"
  if [ -n "$NFQWS_BIN" ]; then
    su -c "cp -f '$NFQWS_BIN' $DEST/nfqws && chmod 755 $DEST/nfqws"
    echo "==> nfqws установлен в $DEST/nfqws"
  else
    echo "Ошибка: nfqws для linux-arm64 не найден в архиве" >&2
    exit 1
  fi
  cd / && rm -rf "$TMP"
else
  echo "==> nfqws уже установлен: $DEST/nfqws"
fi

echo
echo "Готово. Для запуска:"
echo "  bash $DEST/zapret.sh start   — быстрый запуск"
echo "  bash $DEST/service.sh        — меню управления (кнопки)"
echo "  bash $DEST/zapret.sh test    — проверка доступности"
echo "Стратегия меняется в $DEST/zapret.conf (STRATEGY=alt11 по умолчанию)"
