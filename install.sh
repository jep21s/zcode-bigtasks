#!/usr/bin/env bash
# install.sh — установка компонентов zcode-bigtasks:
#   скиллы staged-task / track-task → ~/.agents/skills/
#   zctx                            → ~/.local/bin/
# По умолчанию ставит симлинками — репозиторий остаётся единственным источником
# истины: правка файла в репо сразу видна живому скиллу/скрипту.
#
# Использование:
#   ./install.sh          симлинки (по умолчанию)
#   ./install.sh --copy   копии (для ФС без симлинков)
#
# Существующие файлы/каталоги: идентичные репо — тихо заменяются,
# отличающиеся — сохраняются в .backups/ внутри репо.
# Пути назначения переопределяются: ZCODE_SKILLS_DIR, ZCODE_BIN_DIR.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DST="${ZCODE_SKILLS_DIR:-$HOME/.agents/skills}"
BIN_DST="${ZCODE_BIN_DIR:-$HOME/.local/bin}"
MODE=link

case "${1:-}" in
  "") ;;
  --copy) MODE=copy ;;
  -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  *) echo "неизвестный аргумент: $1 (см. --help)" >&2; exit 2 ;;
esac

# Освободить место под установку: симлинк — снять, идентичное — удалить,
# отличающееся — унести в .backups/.
prepare_target() { # <src> <dst>
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    if diff -r "$dst" "$src" >/dev/null 2>&1; then
      rm -rf "$dst"
    else
      local bak="$REPO/.backups/$(basename "$dst").$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$REPO/.backups"
      mv "$dst" "$bak"
      echo "  ! $dst отличается от репо, бэкап: $bak"
    fi
  fi
}

install_item() { # <src> <dst-dir>
  local src="$1" dst="$2/$(basename "$1")"
  mkdir -p "$2"
  prepare_target "$src" "$dst"
  if [[ "$MODE" == link ]]; then ln -s "$src" "$dst"; else cp -r "$src" "$dst"; fi
  echo "  $(basename "$src") → $dst"
}

command -v jq >/dev/null || echo "ВНИМАНИЕ: jq не найден — zctx без него не работает (apt install jq)"
command -v tac >/dev/null || echo "ВНИМАНИЕ: tac (coreutils) не найден — zctx без него не работает"

echo "Установка zcode-bigtasks (${MODE}) в $SKILLS_DST и $BIN_DST:"
install_item "$REPO/skills/staged-task" "$SKILLS_DST"
install_item "$REPO/skills/track-task"  "$SKILLS_DST"
install_item "$REPO/bin/zctx"           "$BIN_DST"
echo "Готово. Проверка: zctx --help; скиллы подхватятся новым стартом ZCode."
