# Steam News & SteamSpy Data Warehouse

## 1. Projektvorstellung

*Steam News & SteamSpy Data Warehouse zur run-basierten Analyse von Update-Aktivität und Nutzerinteresse*.

Ziel des Projekts war der Aufbau eines reproduzierbaren Data-Warehouse-Stacks, der heterogene Steam-Datenquellen vereinheitlicht und für analytische Auswertungen strukturiert bereitstellt. Im Zentrum steht die Frage, wie sich veröffentlichte News-Aktivitäten (Content-Seite) mit beobachtbaren Plattformmetriken wie Concurrent Users (CCU), Besitzerbereichen oder Bewertungssignalen in einem konsistenten, historisierbaren Modell zusammenführen lassen.

Die Umsetzung erfolgt bewusst als lokal ausführbarer Docker-Stack (PostgreSQL, Python-ETL, optional Apache Superset) und nicht als produktive Cloud-Plattform. Der Fokus liegt auf konzeptioneller Modellierung, Reproduzierbarkeit und analytischer Nachvollziehbarkeit.

---

## 2. Projektumsetzung und Systemarchitektur

Die Systemarchitektur folgt einem klassischen DWH-Ansatz:

Externe Datenquellen (Steam News API, SteamSpy API) → Python-ETL → PostgreSQL Data Warehouse → optionale BI-Schicht (Apache Superset).

Die gesamte Infrastruktur ist containerisiert (docker-compose) mit getrennten Services für Datenbank, ETL-Prozess und BI-Frontend. Die Konfiguration erfolgt über Environment-Variablen, wodurch reproduzierbare Setups und klar getrennte Laufmodi (Initial-Run vs. Incremental-Run) möglich sind.

Der Initial-Run dient der Erstbefüllung aller relevanten Tabellen. Der Incremental-Run ergänzt neue News-Ereignisse und erzeugt einen zusätzlichen Snapshot der SteamSpy-Metriken. Jeder ETL-Lauf wird als eigenständige Instanz historisiert, wodurch Run-basierte Vergleiche möglich sind.

---

## 3. Verwendete Datenquellen

### Steam News API

Endpoint: `ISteamNews/GetNewsForApp/v2`

Geliefert werden News-Ereignisse pro App mit Titel, URL, Zeitstempel, Tags und weiteren Content-Metadaten. Die Daten liegen JSON-basiert und semi-strukturiert vor.

### SteamSpy API

Endpoint: `request=all`

Diese Quelle liefert Snapshot-Metriken pro App, u. a.:

* Concurrent Users (CCU)
* Owners-Range
* Review-Signale (positive/negative)
* Preis- und Discount-Felder
* Nutzungsmetriken (average_*, median_*)

SteamSpy-Daten werden pro ETL-Run als zeitpunktbezogener Snapshot interpretiert.

---

## 4. Datenmodell und ERM

Das implementierte Modell entspricht einem snowflake-ähnlichen Data-Warehouse-Ansatz mit zwei zentralen Faktentabellen:

* `fact_news` (News-Ereignisse)
* `fact_steamspy_stats` (Snapshot-Metriken je Run und App)

Ergänzt wird das Modell durch mehrere Dimensionstabellen:

* `dim_app`
* `dim_timestamp`
* `dim_update_typ`
* `dim_update_content`
* `dim_etl_run`

Eine zentrale Modellierungsentscheidung betrifft die News-IDs: `update_id` ist nicht global eindeutig, sondern nur innerhalb einer App. Das bedeutet, dass dieselbe `update_id` bei unterschiedlichen Apps erneut vorkommen kann. Um dennoch eindeutige Datensätze sicherzustellen, wird die Eindeutigkeit über die Kombination `(app_id, update_id)` hergestellt. Damit wird die reale Eigenschaft der Quelle direkt im relationalen Modell berücksichtigt und technisch korrekt abgesichert.

Die Historisierung erfolgt über `dim_etl_run`. Jeder Lauf erhält Metadaten (Startzeit, Status etc.), wodurch abgeschlossene Runs gezielt analysiert und miteinander verglichen werden können.

Referenzielle Integrität wird über Foreign Keys, Constraints und Indizes sichergestellt.

---

## 5. Erschließung der Datenquellen (ETL-Prozess)

Der ETL-Prozess gliedert sich in zwei Hauptphasen.

### SteamSpy-Phase

* Upsert der App-Stammdaten in `dim_app`
* Insert eines Metrik-Snapshots in `fact_steamspy_stats`
* Parsing der Owners-Range in `owners_min` und `owners_max`
* Typnormalisierung numerischer Felder

### Steam-News-Phase

* Paginiertes Laden der News je App
* Mapping in Zeit-, Typ- und Content-Dimensionen
* Insert in `fact_news`

Beim Incremental-Run wird pro App ein Cutoff-Timestamp verwendet, sodass ausschließlich neue News verarbeitet werden.

Zur Robustheit werden Transaktionsgrenzen auf App-Ebene gesetzt. Duplikaterkennung, Konfliktbehandlung und Skip-Logik bei unvollständigen Datensätzen sichern die Konsistenz. API-Ratenlimits werden über Retry-Strategien und kontrollierte Wartezeiten berücksichtigt.

---

## 6. Datenauswertungen

Die analytische Schicht basiert auf spezifischen SQL-Views (z. B. Overview-, Latest- und Changes-Views), die als semantische Abstraktion über dem Basisschema liegen.

Kernindikatoren sind u. a.:

* `ccu`
* `news_count_7d`
* `news_count_30d`
* `ccu_per_news_30d`
* Preis- und Discount-Felder
* Delta-Metriken zwischen ETL-Runs

Es wurden mehrere Dashboard-Perspektiven umgesetzt:

* App-Detail-Analyse (Drilldown pro Spiel)
* Globaler Snapshot des letzten erfolgreichen Runs
* Run-basierter Vergleich mehrerer Datenstände

Die Auswertung ist explizit als explorative Analyse konzipiert. Beobachtete Zusammenhänge zwischen News-Aktivität und Nutzermetriken werden nicht kausal interpretiert.

---

## 7. Aufgetretene Probleme und Lösungen

Ein zentrales Problem war die fehlende globale Eindeutigkeit der News-IDs. Dieses wurde durch die zusammengesetzte Schlüsseldefinition `(app_id, update_id)` gelöst.

API-Ratenlimits und temporäre Zugriffsbeschränkungen wurden durch Retry-Strategien sowie differenziertes Handling von HTTP-Statuscodes (z. B. 403, 429) adressiert.

Inkonsistenzen während laufender ETL-Prozesse führten zur Einführung eines Run-Status-Konzepts, sodass ausschließlich erfolgreich abgeschlossene Runs ausgewertet werden.

Plattformbedingte Ausführungsprobleme durch unterschiedliche Zeilenenden (CRLF/LF) wurden über `.gitattributes` und Renormalisierung behoben.

---

## 8. Vor- und Nachteile der Umsetzung

### Vorteile

* Klare Trennung von Quellenmapping, ETL-Logik, DWH-Schema und Auswertungsschicht
* Reproduzierbare lokale Ausführung per Docker mit vollständigem Setup über ein einziges Compose-File
* Automatisierter Schema-Init sowie optionaler Import von Dumps und Dashboards
* Smoke-Tests zur technischen Minimalvalidierung des Schemas und zentraler Views
* GitHub-Workflow zur automatisierten Prüfung des Repositories (SQL-Syntax, ETL-Integrität, Initialisierungslogik)
* Run-basierte Historisierung ermöglicht strukturierte Zeitvergleiche zwischen konsistenten Datenständen
* Erweiterbarkeit über zusätzliche Views ohne strukturelle Schemaänderungen
* Transparente und nachvollziehbare Architektur, gut geeignet für Lehr- und Demonstrationszwecke

### Nachteile

* Begrenzter Quellumfang reduziert die statistische Repräsentativität der Ergebnisse
* Die SteamSpy-API ist keine offizielle Valve-Quelle; Datenherkunft und Genauigkeit sind nur eingeschränkt transparent
* CCU-Werte verändern sich zwischen Runs teilweise nur geringfügig, wodurch kurzfristige Effekte schwer sichtbar werden
* Für belastbare Aussagen wäre eine deutlich längere historische Datenbasis erforderlich
* Selbst bei längerer Historie bleibt die Validität der SteamSpy-Metriken methodisch eingeschränkt
* Append-only-Strategie erschwert nachträgliche Datenkorrekturen
* Abhängigkeit von externen API-Strukturen und deren Stabilität

---

## 9. Ausblick

Sinnvolle Weiterentwicklungen betreffen sowohl methodische als auch datenbezogene Aspekte.

* Ausbau formalisierter Data-Quality-Regeln mit run-basierten Qualitätskennzahlen
* Systematische Validierung externer Kennzahlenquellen oder Ergänzung um alternative Datenquellen
* Erweiterung des Modells um zusätzliche Dimensionen (z. B. Genre, Release-Alter, Publisher)
* Vertiefte Zeitreihenanalysen mit Lag-Betrachtungen zur getrennten Analyse kurzfristiger und langfristiger Effekte
* Aufbau eines Monitoring- und Observability-Konzepts für produktionsnahe Szenarien

Die vorliegende Umsetzung ist bewusst als nachvollziehbare Referenzarchitektur konzipiert. Ziel war nicht maximale Datenabdeckung oder statistische Aussagekraft, sondern eine technisch saubere, reproduzierbare und analytisch strukturierte DWH-Implementierung. Die run-basierte Historisierung erlaubt dabei eine konsistente Gegenüberstellung mehrerer Datenstände über die Zeit, auch wenn die Aussagekraft einzelner Kennzahlen durch die Eigenschaften der genutzten Quellen begrenzt bleibt.
