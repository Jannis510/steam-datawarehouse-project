# Konfiguration (Environment Variables)

Diese Dokumentation beschreibt alle relevanten Environment-Variablen des Projekts und deren Einfluss auf den Betrieb des DWH-Stacks sowie des ETL-Prozesses.

**Hinweis:**
Die Datei `.env.example` ist bereits mit **funktionsfähigen Testwerten** befüllt. Für ein einfaches lokales Ausprobieren oder die Projektabgabe ist **keine Anpassung erforderlich**. Änderungen sind nur nötig, wenn Ports, Zugangsdaten oder der Umfang des ETL gezielt angepasst werden sollen.

---

## PostgreSQL / Data Warehouse

| Variable                  | Zweck                                                                   |
| ------------------------- | ----------------------------------------------------------------------- |
| `POSTGRES_CONTAINER_NAME` | Name des PostgreSQL-Containers                                          |
| `POSTGRES_DB`             | Name der DWH-Datenbank                                                  |
| `POSTGRES_USER`           | Datenbankbenutzer                                                       |
| `POSTGRES_PASSWORD`       | Passwort des DB-Benutzers                                               |
| `POSTGRES_PORT`           | Host-Port für PostgreSQL                                                |
| `POSTGRES_HOST`           | Hostname/Service für DB-Verbindungen im Docker-Netz                     |
| `POSTGRES_DUMP_FILE`      | Pfad zu einem Data-only Dump für automatischen Import beim ersten Start |
| `POSTGRES_SMOKE_TEST`     | Aktiviert (1) einen Smoke-Test nach Dump-Import                         |

---

## ETL / Steuerung

| Variable              | Zweck                                                      |
| --------------------- | ---------------------------------------------------------- |
| `ETL_CRON_SCHEDULE`   | Cron-Zeitplan für inkrementelle ETL-Läufe                  |
| `ETL_CRON_SCRIPT`     | Pfad zum ETL-Skript innerhalb des Containers               |
| `ETL_APPS_LIMIT`      | Begrenzung der Apps für Steam News (0 = alle)              |
| `ETL_STEAMSPY_LIMIT`  | Begrenzung der Apps für SteamSpy (0 = alle)                |
| `ETL_SKIP_NEWS`       | Überspringt bei 1 die News-Phase (nur SteamSpy)            |
| `NEWS_MAX_PAGES`      | Maximale Anzahl News-Seiten pro App (0/unset = unbegrenzt) |
| `NEWS_PAGE_SIZE`      | Anzahl News pro Seite beim Steam News API Call             |
| `NEWS_SLEEP_S`        | Pause zwischen Apps (Rate-Limit-Schutz)                    |
| `COMMIT_EVERY_APPS`   | Commit-Intervall während der News-Verarbeitung             |
| `LOG_EVERY`           | Log-Ausgabe-Intervall (z. B. alle N Apps)                  |
| `LOG_CONFLICTS_LIMIT` | Maximale Anzahl geloggter Konflikte                        |
| `TZ`                  | Zeitzone des Containers                                    |

---

## pgAdmin

| Variable                   | Zweck                                   |
| -------------------------- | --------------------------------------- |
| `PGADMIN_CONTAINER_NAME`   | Name des pgAdmin-Containers             |
| `PGADMIN_DEFAULT_EMAIL`    | Login-E-Mail für pgAdmin                |
| `PGADMIN_DEFAULT_PASSWORD` | Login-Passwort für pgAdmin              |
| `PGADMIN_PORT`             | Host-Port für die pgAdmin-Weboberfläche |

---

## Apache Superset

| Variable                         | Zweck                                          |
| -------------------------------- | ---------------------------------------------- |
| `SUPERSET_CONTAINER_NAME`        | Name des Superset-Containers                   |
| `SUPERSET_PORT`                  | Host-Port für die Superset-Weboberfläche       |
| `SUPERSET_ADMIN_USERNAME`        | Benutzername des Superset-Admins               |
| `SUPERSET_ADMIN_PASSWORD`        | Passwort des Superset-Admins                   |
| `SUPERSET_ADMIN_EMAIL`           | E-Mail-Adresse des Superset-Admins             |
| `SUPERSET_SECRET_KEY`            | Secret Key für Superset (nur für Entwicklung)  |
| `SUPERSET_DB_USER`               | Datenbankbenutzer für Superset                 |
| `SUPERSET_DB_PASSWORD`           | Passwort für den Superset-DB-Benutzer          |
| `SUPERSET_DB_NAME`               | Name der Superset-Metadatenbank                |
| `SUPERSET_LOAD_EXAMPLES`         | Beispiel-Daten laden (false empfohlen)         |
| `SUPERSET_IMPORT_DASHBOARDS`     | Aktiviert automatischen Dashboard-Import       |
| `SUPERSET_IMPORT_DIR`            | Import-Quellverzeichnis im Container           |
| `SUPERSET_IMPORT_WORK_DIR`       | Temporäres Arbeitsverzeichnis für Imports      |
| `SUPERSET_IMPORT_OVERWRITE`      | Überschreibt vorhandene Dashboards beim Import |
| `SUPERSET_IMPORT_MARKER`         | Marker-Datei zur Vermeidung mehrfacher Imports |
| `SUPERSET_IMPORT_SQLALCHEMY_URI` | Optionaler SQLAlchemy-URI für Dashboard-Import |
| `SUPERSET_IMPORT_FORCE_URI`      | Erzwingt Nutzung der Import-URI                |
| `DWH_SQLALCHEMY_URI`             | SQLAlchemy-URI für Zugriff auf das DWH         |
| `SUPERSET_CONFIG_PATH`           | Pfad zur Superset-Konfigurationsdatei          |

---

## Zusammenfassung

Die Environment-Konfiguration ermöglicht eine flexible Steuerung des gesamten Stacks (Datenbank, ETL, Visualisierung). Die bereitgestellten Default-Werte sind bewusst so gewählt, dass das Projekt ohne weitere Anpassungen lokal ausgeführt und bewertet werden kann.
