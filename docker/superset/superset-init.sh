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

# 4) Server starten
exec /usr/bin/run-server.sh
