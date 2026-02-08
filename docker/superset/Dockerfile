FROM apache/superset:3.1.0

USER root
RUN python -m pip install --no-cache-dir psycopg2-binary

COPY superset-init.sh /superset-init.sh
RUN chmod +x /superset-init.sh

COPY superset_config.py /app/superset_config.py
ENV SUPERSET_CONFIG_PATH=/app/superset_config.py

ENTRYPOINT ["/superset-init.sh"]
