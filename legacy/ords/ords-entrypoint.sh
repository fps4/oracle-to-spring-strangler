#!/bin/bash
# ORDS container entrypoint: explicit install-then-serve instead of the
# image's magic-file convention -- transparent and debuggable (FS-0001).
# First boot installs ORDS into XEPDB1 (persisted in the ords-config
# volume); later boots go straight to serve.
set -euo pipefail

CONFIG_DIR=/etc/ords/config

if [ ! -f "${CONFIG_DIR}/databases/default/pool.xml" ]; then
  echo "[ords] no config found -- installing ORDS into ${DB_HOST:-oracle}:1521/${DB_SERVICE:-XEPDB1}"
  echo "${ORACLE_PASSWORD:?ORACLE_PASSWORD is required}" | \
    ords --config "${CONFIG_DIR}" install \
      --admin-user "SYS AS SYSDBA" \
      --db-hostname "${DB_HOST:-oracle}" \
      --db-port 1521 \
      --db-servicename "${DB_SERVICE:-XEPDB1}" \
      --feature-sdw false \
      --feature-db-api false \
      --feature-rest-enabled-sql false \
      --log-folder /tmp/ords-install \
      --password-stdin
else
  echo "[ords] existing config found -- skipping install"
fi

exec ords --config "${CONFIG_DIR}" serve
