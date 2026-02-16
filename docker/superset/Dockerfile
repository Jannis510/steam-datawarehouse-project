FROM apache/superset:3.1.0

USER root
# Add PostgreSQL driver for Superset metadata and external DB connections.
RUN python -m pip install --no-cache-dir psycopg2-binary

COPY superset-init.sh /superset-init.sh
RUN chmod +x /superset-init.sh

COPY superset_config.py /app/superset_config.py
COPY patch_superset_imports.py /app/patch_superset_imports.py
# Load project-specific Superset config at runtime.
ENV SUPERSET_CONFIG_PATH=/app/superset_config.py

ENTRYPOINT ["/superset-init.sh"]
