#!/usr/bin/env bash
# tests/test_zctx.sh — проверки bin/zctx на фикстурах tests/fixtures/rollout/.
# Запуск из любого каталога: bash tests/test_zctx.sh. rc = 0 ⇔ все проверки прошли.
#
# Живой ~/.zcode/cli/rollout не трогается: фикстуры копируются во временный каталог,
# он подставляется через ZCTX_ROLLDIR; mtime файлов задаются здесь же (сессия выбирается по свежести).
# Известные числа фикстур (usage inputTokens/outputTokens по порядку записей):
#   main     (5 записей с usage + 1 строка без usage): 79000/1500, 80700/2400, 83400/1900, 85400/3100, 88800/1200
#   subagent (4 записи с usage + оборванная строка):   14926/192, 15480/98, 28448/237, 32190/821
#   nousage  (usage нет ни в одной записи)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZCTX="$ROOT/bin/zctx"
FIX="$ROOT/tests/fixtures/rollout"
[[ -f "$ZCTX" && -d "$FIX" ]] || { echo "не найдены bin/zctx или tests/fixtures/rollout относительно $ROOT" >&2; exit 2; }
command -v jq >/dev/null || { echo "нужен jq" >&2; exit 2; }

TMP="$(mktemp -d /tmp/zctx-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"

cp "$FIX"/*.jsonl "$TMP"/
T0=$(date +%s)
touch -d "@$((T0 - 180))" "$TMP"/model-io-sess_bbbbbbbb-*.jsonl          # без usage — старейший
touch -d "@$((T0 - 120))" "$TMP"/model-io-sess_aaaaaaaa-*.jsonl          # основная сессия
touch -d "@$((T0 - 60))"  "$TMP"/model-io-sess_subagent_agent_*.jsonl    # субагент — самый свежий

export ZCTX_ROLLDIR="$TMP" ZCTX_LIMIT=1000000
export ZCTX_WARN_AT=""

MAIN_F="model-io-sess_aaaaaaaa-0000-4000-8000-000000000002.jsonl"
SUB_F="model-io-sess_subagent_agent_11111111-0000-4000-8000-000000000001.jsonl"
MAIN_LEGACY="session $MAIN_F
context 90000 / 1000000 (9%) [ok]"
SUB_LEGACY="session $SUB_F
context 33011 / 1000000 (3%) [ok]"
SUB_LEGACY_JSON="{
  \"file\": \"$SUB_F\",
  \"used\": 33011,
  \"limit\": 1000000,
  \"percent\": 3,
  \"warnAt\": null,
  \"inputTokens\": 32190,
  \"outputTokens\": 821,
  \"status\": \"ok\"
}"
MAIN_BASE_JSON="{\"file\":\"$MAIN_F\",\"used\":90000,\"limit\":1000000,\"percent\":9,\"warnAt\":null,\"inputTokens\":88800,\"outputTokens\":1200,\"status\":\"ok\""

PASS=0; FAIL=0
# check <описание> <ожидаемый rc> <ожидаемый вывод (дословно)> <команда…>
check() {
  local desc="$1" want_rc="$2" want="$3"; shift 3
  local rc=0 out
  out=$("$@" 2>&1) || rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "ok $((PASS + FAIL)) - $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $((PASS + FAIL)) - $desc"
    echo "    rc:     $rc (ожидался $want_rc)"
    echo "    вывод:  ${out//$'\n'/ | }"
    echo "    ожидал: ${want//$'\n'/ | }"
  fi
}
legacy_both() { "$ZCTX"; "$ZCTX" --json; }
help_has_new_flags() { local h; h=$("$ZCTX" --help) && [[ "$h" == *--main* && "$h" == *--delta* ]]; }

check "--main выбирает файл без «subagent» в имени, а не самый свежий" 0 "$MAIN_LEGACY" "$ZCTX" --main
check "без флагов — как прежде: самый свежий файл (с недописанной строкой), текст и --json" 0 "$SUB_LEGACY
$SUB_LEGACY_JSON" legacy_both
check "явный -s приоритетнее --main" 0 "$SUB_LEGACY" "$ZCTX" -s 11111111 --main
check "--main --delta 3: точные числа" 0 "session $MAIN_F  delta +6600, requests 3 (83400 → 90000): свои ответы 6200 (93%), инструменты и прочее 400" \
  "$ZCTX" --main --delta 3
check "--json --main --delta 3: поля deltaStart/delta/own/other/ownPct/requests, одна строка" 0 \
  "$MAIN_BASE_JSON,\"deltaStart\":83400,\"delta\":6600,\"own\":6200,\"other\":400,\"ownPct\":93,\"requests\":3}" \
  "$ZCTX" --json --main --delta 3
check "--delta без N: по умолчанию 20, N не съедает следующий флаг, записи без usage не считаются" 0 \
  "$MAIN_BASE_JSON,\"deltaStart\":79000,\"delta\":11000,\"own\":10100,\"other\":900,\"ownPct\":91,\"requests\":5}" \
  "$ZCTX" --main --delta --json
check "-s <субагент> --delta 2: точные числа" 0 \
  "session $SUB_F  delta +4563, requests 2 (28448 → 33011): свои ответы 1058 (23%), инструменты и прочее 3505" \
  "$ZCTX" -s 11111111 --delta 2
check "оборванная (недописанная) строка файла не считается" 0 \
  "session $SUB_F  delta +18085, requests 4 (14926 → 33011): свои ответы 1348 (7%), инструменты и прочее 16737" \
  "$ZCTX" -s 11111111 --delta
check "ошибка: неизвестная сессия" 1 "session not found: nosuchsession" "$ZCTX" -s nosuchsession
check "ошибка: файл без usage" 1 "no usage records in $TMP/model-io-sess_bbbbbbbb-0000-4000-8000-000000000003.jsonl" \
  "$ZCTX" -s bbbbbbbb --delta
check "ошибка: нет основной сессии (нет model-io-* без «subagent»)" 1 \
  "main session not found: no model-io-*.jsonl without \"subagent\" in name in $EMPTY" \
  env ZCTX_ROLLDIR="$EMPTY" "$ZCTX" --main
check "ошибка: в каталоге нет транскриптов" 1 "no rollout files in $EMPTY" env ZCTX_ROLLDIR="$EMPTY" "$ZCTX"
check "--help описывает новые флаги" 0 "" help_has_new_flags

printf 'итог: %d прошло, %d провалено\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
