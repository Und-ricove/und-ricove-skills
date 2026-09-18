#!/usr/bin/env bash
# Доска действий мультисессии: несколько сессий Claude Code на одной машине
# пишут свои действия в ОДИН файл последовательно, под замком.
# Перед действием — claim (без записи действовать нельзя), после — done
# (строка стирается). Замок — каталог board.lock (mkdir атомарен): «файл
# открыт другой сессией» = замок есть — ждём. Журнал board.log — для разбора
# конфликтов. Идентификатор сессии — первые 8 символов CLAUDE_CODE_SESSION_ID.
#
#   board.sh claim <зона> <описание…> [--wait=СЕК]   → 0 записано, 3 ЗАНЯТО
#   board.sh done  <зона>                            → строка снята
#   board.sh show                                    → доска и id
#   board.sh id
set -u
BOARD="${BOARD_FILE:-$HOME/.claude/board.md}"
LOCK="${BOARD_LOCK:-$HOME/.claude/board.lock}"
LOG="${BOARD_LOG:-$HOME/.claude/board.log}"
SID="${BOARD_ID:-${CLAUDE_CODE_SESSION_ID:-manual}}"
SID="${SID:0:8}"
LOCK_STALE=120      # секунд: замок старше — снимается (сессия умерла под замком)
LINE_DEAD=14400     # секунд: строка старше 4 ч — мёртвая сессия, снимается

now() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s [%s] %s\n' "$(now)" "$SID" "$*" >> "$LOG"; }

take_lock() {
  local i=0 age
  while ! mkdir "$LOCK" 2>/dev/null; do
    age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -gt "$LOCK_STALE" ]; then
      log "снят устаревший замок (${age} с): $(cat "$LOCK/owner" 2>/dev/null || echo '?')"
      rm -rf "$LOCK" 2>/dev/null
      continue
    fi
    i=$((i + 1))
    if [ "$i" -gt 90 ]; then
      echo "🔴 доска: замок занят дольше полутора минут — $(cat "$LOCK/owner" 2>/dev/null)"
      return 1
    fi
    sleep 1
  done
  printf '%s %s\n' "$SID" "$(now)" > "$LOCK/owner"
}
drop_lock() { rm -rf "$LOCK" 2>/dev/null; }

ensure_board() {
  [ -f "$BOARD" ] || printf '# Доска действий (мультисессия). Не править руками — только board.sh.\n' > "$BOARD"
}

# Строки мёртвых сессий (старше LINE_DEAD) снимаются с записью в журнал.
sweep_dead() {
  local cut before after
  cut=$(( $(date +%s) - LINE_DEAD ))
  before=$(grep -c '^- \[' "$BOARD" 2>/dev/null || echo 0)
  awk -v cut="$cut" -F'|' '
    /^- \[/ { split($2, a, " "); if (a[1] + 0 < cut) { print "мёртвая строка снята: " $0 > "/dev/stderr"; next } }
    { print }' "$BOARD" > "$BOARD.tmp" && mv -f "$BOARD.tmp" "$BOARD"
  after=$(grep -c '^- \[' "$BOARD" 2>/dev/null || echo 0)
  [ "$before" != "$after" ] && log "снято мёртвых строк: $((before - after))"
  return 0
}

# Строка: - [sid | epoch | дата время] зона: описание
claim() {
  local zone="$1"; shift
  local wait=0 desc=() a d t0 busy
  for a in "$@"; do
    case "$a" in
      --wait=*) wait="${a#--wait=}" ;;
      *) desc+=("$a") ;;
    esac
  done
  d="${desc[*]:-}"
  t0=$(date +%s)
  while :; do
    take_lock || return 1
    ensure_board
    sweep_dead
    busy=$(grep -E "^- \[[0-9a-f]{8} \| [0-9]+ \| [^]]+\] ${zone}: " "$BOARD" | grep -Ev "^- \[${SID} " || true)
    if [ -n "$busy" ]; then
      drop_lock
      if [ $(( $(date +%s) - t0 )) -ge "$wait" ]; then
        echo "⛔ ЗАНЯТО ${zone} — другая сессия: ${busy}"
        log "занято ${zone} (ждал ${wait} с): ${busy}"
        return 3
      fi
      sleep 5
      continue
    fi
    grep -Ev "^- \[${SID} \| [0-9]+ \| [^]]+\] ${zone}: " "$BOARD" > "$BOARD.tmp" || true
    printf -- '- [%s | %s | %s] %s: %s\n' "$SID" "$(date +%s)" "$(now)" "$zone" "$d" >> "$BOARD.tmp"
    mv -f "$BOARD.tmp" "$BOARD"
    log "claim ${zone}: ${d}"
    drop_lock
    echo "✓ ${SID} ${zone}: ${d}"
    return 0
  done
}

done_zone() {
  local zone="$1"
  take_lock || return 1
  ensure_board
  grep -Ev "^- \[${SID} \| [0-9]+ \| [^]]+\] ${zone}: " "$BOARD" > "$BOARD.tmp" || true
  mv -f "$BOARD.tmp" "$BOARD"
  log "done ${zone}"
  drop_lock
  echo "✓ ${SID} снято: ${zone}"
}

case "${1:-}" in
  claim) [ $# -ge 2 ] || { echo "board.sh claim <зона> <описание…> [--wait=СЕК]"; exit 2; }; shift; claim "$@" ;;
  done)  [ $# -ge 2 ] || { echo "board.sh done <зона>"; exit 2; }; done_zone "$2" ;;
  show)  ensure_board; echo "я: ${SID}"; cat "$BOARD"; [ -d "$LOCK" ] && echo "(замок держит: $(cat "$LOCK/owner" 2>/dev/null))"; exit 0 ;;
  id)    echo "$SID" ;;
  *)     sed -n '2,12p' "$0"; exit 2 ;;
esac
