# Mapping: Steam News API -> DWH

## Beispiel (kurz)

```
{
  "gid": "1816307528930061",
  "title": "Counter-Strike 2 Update",
  "url": "https://steamstore-a.akamaihd.net/news/...",
  "is_external_url": true,
  "author": "Piggles ULTRAPRO",
  "contents": "[p]...",
  "feedlabel": "Community Announcements",
  "date": 1763082076,
  "feedname": "steam_community_announcements",
  "feed_type": 1,
  "appid": 730,
  "tags": ["patchnotes"]
}
```

## Mapping-Tabelle

| API-Feld           | Ziel im DWH                                        | Begründung            |
| ------------------ | -------------------------------------------------- |-----------------------|
| `gid`              | `fact_news.update_id`, `dim_update_content.update_id` | Event- und Content-ID |
| `title`            | `fact_news.title`                                  | Event-Metadaten       |
| `url`              | `fact_news.url`                                    | Event-Metadaten       |
| `appid`            | `fact_news.app_id`, `dim_app.app_id`               | App-Referenz          |
| `date`             | `fact_news.timestamp_id` -> `dim_timestamp`        | Zeitdimension         |
| `tags[0]`          | `fact_news.update_type_id` -> `dim_update_typ`     | Klassifikation        |
| `contents`         | `dim_update_content.content_raw`                   | Volltext              |
| `author`           | `dim_update_content.author`                        | Content-Metadaten     |
| `feedlabel`        | `dim_update_content.feedlabel`                     | Content-Metadaten     |
| `feedname`         | `dim_update_content.feedname`                      | Content-Metadaten     |
| `feed_type`        | `dim_update_content.feedtype`                      | Content-Metadaten     |
| `is_external_url`  | `dim_update_content.is_external_url`               | Content-Metadaten     |
| `tags` (alle)      | `dim_update_content.tags_raw`                      | Rohdaten              |

Hinweis: `update_id` ist nur pro App eindeutig, daher nutzt `dim_update_content` den Schlüssel (`app_id`, `update_id`).
