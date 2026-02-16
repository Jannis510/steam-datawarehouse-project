import os

FEATURE_FLAGS = {
    # Required for Jinja-based SQL templating in dashboards/charts.
    "ENABLE_TEMPLATE_PROCESSING": True,
}

ENABLE_PROXY_FIX = True
# Keep secrets and DB connection configurable via environment variables.
SECRET_KEY = os.getenv("SUPERSET_SECRET_KEY", "change-me")
SQLALCHEMY_DATABASE_URI = os.getenv(
    "SQLALCHEMY_DATABASE_URI",
    "postgresql+psycopg2://superset:superset@postgres:5432/superset",
)
