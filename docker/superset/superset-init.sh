#!/bin/bash
set -e

# 1) Metastore migrieren
superset db upgrade

# 2) Admin anlegen (CLI ohne --admin)
# Falls User schon existiert: create-admin scheitert -> dann Passwort resetten
superset fab create-admin \
  --username "$ADMIN_USERNAME" \
  --firstname Superset \
  --lastname Admin \
  --email "$ADMIN_EMAIL" \
  --password "$ADMIN_PASSWORD" \
  || superset fab reset-password \
      --username "$ADMIN_USERNAME" \
      --password "$ADMIN_PASSWORD"

# 3) Rollen/Perms initialisieren
superset init

# 3b) Dashboards importieren (optional, nur einmal)
IMPORT_DASHBOARDS="${SUPERSET_IMPORT_DASHBOARDS:-0}"
IMPORT_DIR="${SUPERSET_IMPORT_DIR:-/app/imports}"
IMPORT_WORK_DIR="${SUPERSET_IMPORT_WORK_DIR:-/tmp/imports}"
IMPORT_OVERWRITE="${SUPERSET_IMPORT_OVERWRITE:-1}"
IMPORT_MARKER="${SUPERSET_IMPORT_MARKER:-/app/superset_home/.dashboards_imported}"

if [ "$IMPORT_DASHBOARDS" = "1" ] && [ -d "$IMPORT_DIR" ]; then
  if [ ! -f "$IMPORT_MARKER" ]; then
    python /app/patch_superset_imports.py "$IMPORT_DIR" "$IMPORT_WORK_DIR"
    found=0
    while IFS= read -r -d '' file; do
      found=1
      echo "Importing Superset dashboard: $file"
      if [ "$IMPORT_OVERWRITE" = "1" ]; then
        echo "Warning: --overwrite not supported by this Superset version, importing without overwrite."
      fi
      superset import-dashboards -p "$file" -u "$ADMIN_USERNAME"
    done < <(find "$IMPORT_WORK_DIR" -maxdepth 1 -type f -name '*.zip' -print0)
    if [ "$found" = "1" ]; then
      touch "$IMPORT_MARKER"
    else
      echo "No Superset dashboard exports found in $IMPORT_WORK_DIR"
    fi
  else
    echo "Superset dashboards already imported (marker found)."
  fi
fi

# 4) Server starten
exec /usr/bin/run-server.sh
