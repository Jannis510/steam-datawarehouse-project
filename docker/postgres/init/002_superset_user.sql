-- Superset metadata database + user
CREATE USER superset WITH PASSWORD 'superset';
CREATE DATABASE superset OWNER superset;
GRANT ALL PRIVILEGES ON DATABASE superset TO superset;
