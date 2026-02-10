# Mapping: SteamSpy API -> DWH

## Beispiel (kurz)

```
{
  "730": {
    "appid": 730,
    "name": "Counter-Strike: Global Offensive",
    "developer": "Valve",
    "publisher": "Valve",
    "positive": 7642084,
    "negative": 1173003,
    "userscore": 0,
    "owners": "100,000,000 .. 200,000,000",
    "average_forever": 33464,
    "average_2weeks": 737,
    "median_forever": 6341,
    "median_2weeks": 299,
    "price": "0",
    "initialprice": "0",
    "discount": "0",
    "ccu": 1013936
  }
}
```

## Mapping-Tabelle

| API-Feld           | Ziel im DWH                                     | Begründung         |
| ------------------ | ---------------------------------------------- |--------------------|
| `appid`            | `fact_steamspy_stats.app_id`, `dim_app.app_id`  | Fremdschluessel    |
| `name`             | `dim_app.app_name`                              | Stammdaten         |
| `developer`        | `dim_app.developer`                             | Stammdaten         |
| `publisher`        | `dim_app.publisher`                             | Stammdaten         |
| `owners`           | `owners_min`, `owners_max`                      | Range in zwei INTs |
| `ccu`              | `fact_steamspy_stats.ccu`                       | Snapshot-Metrik    |
| `positive`         | `fact_steamspy_stats.positive`                  | Snapshot-Metrik    |
| `negative`         | `fact_steamspy_stats.negative`                  | Snapshot-Metrik    |
| `userscore`        | `fact_steamspy_stats.userscore`                 | Snapshot-Metrik    |
| `average_forever`  | `fact_steamspy_stats.average_forever`           | Snapshot-Metrik    |
| `median_forever`   | `fact_steamspy_stats.median_forever`            | Snapshot-Metrik    |
| `average_2weeks`   | `fact_steamspy_stats.average_2weeks`            | Snapshot-Metrik    |
| `median_2weeks`    | `fact_steamspy_stats.median_2weeks`             | Snapshot-Metrik    |
| `price`            | `fact_steamspy_stats.price`                     | Snapshot-Metrik    |
| `initialprice`     | `fact_steamspy_stats.initialprice`              | Snapshot-Metrik    |
| `discount`         | `fact_steamspy_stats.discount`                  | Snapshot-Metrik    |

Hinweis: Für den Uni-Umfang wird nur Seite 0 des `all`-Endpoints geladen (1000 größte Spiele).
