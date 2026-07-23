#!/bin/bash
# =====================================================================
# One-shot ORDS module configuration (compose service: ords-config).
#
# The ORDS PL/SQL API only exists in the database AFTER the ords
# container has installed its metadata schema on first startup, so the
# REST module definitions cannot run as a DB init script. This script
# waits for that install, then defines the modules as LEGACY.
# Runs inside the gvenzl/oracle-xe image (for sqlplus); exits 0 on done.
# =====================================================================
set -euo pipefail

DB_HOST="${DB_HOST:-oracle}"
DB_SERVICE="${DB_SERVICE:-XEPDB1}"
LEGACY_PASSWORD="${LEGACY_PASSWORD:?LEGACY_PASSWORD is required}"
CONN="legacy/${LEGACY_PASSWORD}@//${DB_HOST}:1521/${DB_SERVICE}"
SQLPLUS="$(command -v sqlplus || echo /opt/oracle/product/21c/dbhomeXE/bin/sqlplus)"

echo "[ords-config] waiting for database + ORDS install..."
for i in $(seq 1 180); do
  READY=$("$SQLPLUS" -s "$CONN" <<'EOF' 2>/dev/null | tr -d '[:space:]' || true
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM all_synonyms WHERE synonym_name = 'ORDS' AND owner = 'PUBLIC';
EXIT
EOF
)
  if [ "$READY" = "1" ]; then
    echo "[ords-config] ORDS PL/SQL API available (waited ${i}0s)"
    break
  fi
  if [ "$i" = "180" ]; then
    echo "[ords-config] ERROR: ORDS install not detected after 30 min" >&2
    exit 1
  fi
  sleep 10
done

echo "[ords-config] defining REST modules..."
"$SQLPLUS" -s "$CONN" @/ords-config/modules.sql
echo "[ords-config] done."
