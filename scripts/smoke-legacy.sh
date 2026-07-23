#!/bin/bash
# =====================================================================
# M0 smoke test (FS-0001 definition of done): the four ORDS endpoints
# answer correctly against pinned seed anchors, including the TRUNC
# rounding quirk and both named-exception error paths.
#
# Host resolution: honors ORDS_URL; else derives the host from
# DOCKER_HOST (ssh://user@host -> host); else localhost.
# No jq dependency -- grep-based assertions only.
# =====================================================================
set -uo pipefail

if [ -z "${ORDS_URL:-}" ]; then
  host=localhost
  case "${DOCKER_HOST:-}" in
    ssh://*) host="${DOCKER_HOST#ssh://}"; host="${host%%:*}"; host="${host#*@}" ;;
  esac
  ORDS_URL="http://${host}:8081"
fi
BASE="${ORDS_URL}/ords/legacy"

PASS=0; FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  ok: $*"; }
bad()  { FAIL=$((FAIL+1)); say "  FAIL: $*"; }

# assert_contains <label> <haystack> <needle>
assert_contains() {
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- expected [$3] in: $(echo "$2" | head -c 300)" ;; esac
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$3" = "$2" ]; then ok "$1"; else bad "$1 -- expected $2, got $3"; fi
}

say "smoke-legacy against ${BASE}"

say "waiting for ORDS + module config (up to 15 min on first boot)..."
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE}/pricing/quote?customer_id=1&product_id=1000&qty=1" || true)
  [ "$code" = "200" ] && break
  [ "$i" = "90" ] && { say "FAIL: quote endpoint never returned 200 (last: $code)"; exit 1; }
  sleep 10
done
say "endpoint is up."

# 1. quote: pinned anchor -- customer 1 (class A, 10%), product 1000 @19.99
body=$(curl -s "${BASE}/pricing/quote?customer_id=1&product_id=1000&qty=1")
assert_contains "quote basic class discount" "$body" '"unit_price":17.99'

# 2. THE TRUNC QUIRK: product 1002 list 12.3456, customer 3 (class C, 0%)
#    -> TRUNC(12.3456,2)=12.34 (ROUND would give 12.35 -- the frozen bug)
body=$(curl -s "${BASE}/pricing/quote?customer_id=3&product_id=1002&qty=1")
assert_contains "TRUNC half-down quirk" "$body" '"unit_price":12.34'

# 3. quote with volume tier: product 1000 qty 50 -> tier 10% + class A 10%
#    19.99*0.9*0.9 = 16.1919 -> 16.19
body=$(curl -s "${BASE}/pricing/quote?customer_id=1&product_id=1000&qty=50")
assert_contains "volume tier discount" "$body" '"unit_price":16.19'
assert_contains "tier pct reported" "$body" '"tier_disc_pct":10'

# 4. promo override: product 1004 promo_price 19.9999, customer 3 qty 1
#    19.9999 < 24.68 -> promo wins -> TRUNC -> 19.99
body=$(curl -s "${BASE}/pricing/quote?customer_id=3&product_id=1004&qty=1")
assert_contains "promotion override" "$body" '"promo_applied":"Y"'
assert_contains "promo price truncated" "$body" '"unit_price":19.99'

# 5. unknown product -> 404
code=$(curl -s -o /dev/null -w '%{http_code}' \
  "${BASE}/pricing/quote?customer_id=1&product_id=999999&qty=1")
assert_eq "quote 404 on unknown product" 404 "$code"

# 6. place order: customer 1, product 1000 qty 5 -> 17.99*5 = 89.95
body=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":1,"lines":[{"product_id":1000,"qty":5}]}' "${BASE}/orders")
assert_contains "place order total" "$body" '"total":89.95'
order_id=$(echo "$body" | grep -o '"order_id":[0-9]*' | grep -o '[0-9]*')
if [ -n "$order_id" ]; then ok "order id returned ($order_id)"; else bad "no order_id in: $body"; fi

# 7. read the order back
body=$(curl -s "${BASE}/orders/${order_id}")
assert_contains "order readback status" "$body" '"status":"OPEN"'
assert_contains "order readback line" "$body" '"unit_price":17.99'

# 8. credit limit exceeded: customer 3 (limit 500) big order -> 422 / ORA-20001
body=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":3,"lines":[{"product_id":1000,"qty":100}]}' "${BASE}/orders")
code=$(echo "$body" | tail -1)
assert_contains "credit exceeded error code" "$body" 'ORA-20001'
assert_eq "credit exceeded -> 422" 422 "$code"

# 9. insufficient stock: product 1003 has 5 on hand -> 409 / ORA-20002
body=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":1,"lines":[{"product_id":1003,"qty":100}]}' "${BASE}/orders")
code=$(echo "$body" | tail -1)
assert_contains "insufficient stock error code" "$body" 'ORA-20002'
assert_eq "insufficient stock -> 409" 409 "$code"

# 10. statements run: fixed seed guarantees orders in 2026-05
body=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"period":"2026-05"}' "${BASE}/statements/run")
assert_contains "statements run period" "$body" '"period":"2026-05"'
if echo "$body" | grep -qE '"statements":[1-9][0-9]*'; then
  ok "statements produced (>0)"
else
  bad "no statements in: $body"
fi

# 11. bad period -> 400 / ORA-20003
body=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"period":"2007-13"}' "${BASE}/statements/run")
code=$(echo "$body" | tail -1)
assert_contains "bad period error code" "$body" 'ORA-20003'
assert_eq "bad period -> 400" 400 "$code"

say ""
say "smoke-legacy: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" = "0" ]
