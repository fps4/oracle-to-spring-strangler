#!/bin/bash
# =====================================================================
# M1 smoke test (FS-0003/FS-0004 definition of done):
#   1. pricing-service answers the pinned anchors directly (port 8082)
#      -- same values smoke-legacy.sh proves against Oracle.
#   2. the router answers on the unified port 8080 and every response
#      carries X-Served-By naming the stack waves.yml routes to.
#
# The router assertions read the expected backend FROM waves.yml, so
# this same script passes before and after a wave flip (the flip PR
# changes waves.yml, not this script).
#
# Host resolution mirrors smoke-legacy.sh: TARGET_URL/ROUTER_URL env
# override; else derive from DOCKER_HOST; else localhost.
# =====================================================================
set -uo pipefail

host=localhost
case "${DOCKER_HOST:-}" in
  ssh://*) host="${DOCKER_HOST#ssh://}"; host="${host%%:*}"; host="${host#*@}" ;;
esac
TARGET_URL="${TARGET_URL:-http://${host}:8082}"
ROUTER_URL="${ROUTER_URL:-http://${host}:8080}"
WAVES_FILE="$(dirname "$0")/../strangler/waves.yml"

PASS=0; FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  ok: $*"; }
bad()  { FAIL=$((FAIL+1)); say "  FAIL: $*"; }

assert_contains() {
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- expected [$3] in: $(echo "$2" | head -c 300)" ;; esac
}

assert_eq() {
  if [ "$3" = "$2" ]; then ok "$1"; else bad "$1 -- expected $2, got $3"; fi
}

# expected_backend <path> -- reads the routed backend for a path out of
# waves.yml (the same constrained schema generate_router_config.py reads)
expected_backend() {
  awk -v want="$1" '
    /- path:/    { path = $NF }
    /backend:/   { if (path == want) { print $NF; exit } }
  ' "$WAVES_FILE"
}

say "smoke-m1: target ${TARGET_URL}, router ${ROUTER_URL}"

# ---- 1. target service direct (FS-0003) -----------------------------

say "waiting for pricing-service readiness (up to 3 min)..."
for i in $(seq 1 36); do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${TARGET_URL}/actuator/health/readiness" || true)
  [ "$code" = "200" ] && break
  if [ "$i" = "36" ]; then say "FAIL: readiness never returned 200 (last: $code)"; exit 1; fi
  sleep 5
done
say "pricing-service is up."

# same pinned anchors as smoke-legacy.sh -- the values must agree
body=$(curl -s "${TARGET_URL}/api/pricing/quote?customer_id=1&product_id=1000&qty=1")
assert_contains "target: class-A discount" "$body" '"unit_price":17.99'

body=$(curl -s "${TARGET_URL}/api/pricing/quote?customer_id=3&product_id=1002&qty=1")
assert_contains "target: TRUNC half-down quirk" "$body" '"unit_price":12.34'

body=$(curl -s "${TARGET_URL}/api/pricing/quote?customer_id=1&product_id=1000&qty=50")
assert_contains "target: volume tier discount" "$body" '"unit_price":16.19'

body=$(curl -s "${TARGET_URL}/api/pricing/quote?customer_id=3&product_id=1004&qty=1")
assert_contains "target: promotion override" "$body" '"promo_applied":"Y"'
assert_contains "target: promo price truncated" "$body" '"unit_price":19.99'

code=$(curl -s -o /dev/null -w '%{http_code}' \
  "${TARGET_URL}/api/pricing/quote?customer_id=1&product_id=999999&qty=1")
assert_eq "target: 404 on unknown product" 404 "$code"

# order on the target store: same pricing, RFC 7807 on errors
body=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":1,"lines":[{"product_id":1000,"qty":5}]}' "${TARGET_URL}/api/orders")
assert_contains "target: place order total" "$body" '"total":89.95'

body=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":3,"lines":[{"product_id":1000,"qty":100}]}' "${TARGET_URL}/api/orders")
code=$(echo "$body" | tail -1)
assert_eq "target: credit exceeded -> 422" 422 "$code"
assert_contains "target: credit problem carries ORA code" "$body" 'ORA-20001'

body=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"period":"2007-13"}' "${TARGET_URL}/api/statements/run")
code=$(echo "$body" | tail -1)
assert_eq "target: bad period -> 400" 400 "$code"
assert_contains "target: bad period problem carries ORA code" "$body" 'ORA-20003'

body=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"period":"2026-05"}' "${TARGET_URL}/api/statements/run")
assert_contains "target: statements run answers" "$body" '"period":"2026-05"'

# OpenAPI + prometheus surfaces exist (FS-0003 scope 4/6)
code=$(curl -s -o /dev/null -w '%{http_code}' "${TARGET_URL}/v3/api-docs")
assert_eq "target: OpenAPI served" 200 "$code"
code=$(curl -s -o /dev/null -w '%{http_code}' "${TARGET_URL}/actuator/prometheus")
assert_eq "target: prometheus endpoint" 200 "$code"

# ---- 2. router (FS-0004) --------------------------------------------

code=$(curl -s -o /dev/null -w '%{http_code}' "${ROUTER_URL}/router/healthz")
assert_eq "router: healthz" 200 "$code"

quote_backend=$(expected_backend /api/pricing/quote)
say "waves.yml routes /api/pricing/quote -> ${quote_backend}"

hdr=$(curl -s -D - -o /dev/null \
  "${ROUTER_URL}/api/pricing/quote?customer_id=1&product_id=1000&qty=1")
assert_contains "router: X-Served-By matches waves.yml" "$hdr" "X-Served-By: ${quote_backend}"

body=$(curl -s "${ROUTER_URL}/api/pricing/quote?customer_id=1&product_id=1000&qty=1")
assert_contains "router: quote answer unchanged through router" "$body" '"unit_price":17.99'

body=$(curl -s "${ROUTER_URL}/api/pricing/quote?customer_id=3&product_id=1002&qty=1")
assert_contains "router: TRUNC quirk through router" "$body" '"unit_price":12.34'

orders_backend=$(expected_backend /api/orders)
hdr=$(curl -s -D - -o /dev/null -X POST -H 'Content-Type: application/json' \
  -d '{"customer_id":1,"lines":[{"product_id":1000,"qty":1}]}' "${ROUTER_URL}/api/orders")
assert_contains "router: orders served by ${orders_backend}" "$hdr" "X-Served-By: ${orders_backend}"

stmt_backend=$(expected_backend /api/statements/run)
hdr=$(curl -s -D - -o /dev/null -X POST -H 'Content-Type: application/json' \
  -d '{"period":"2026-05"}' "${ROUTER_URL}/api/statements/run")
assert_contains "router: statements served by ${stmt_backend}" "$hdr" "X-Served-By: ${stmt_backend}"

code=$(curl -s -o /dev/null -w '%{http_code}' "${ROUTER_URL}/api/nonexistent")
assert_eq "router: unrouted path -> 404" 404 "$code"

say ""
say "smoke-m1: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" = "0" ]
