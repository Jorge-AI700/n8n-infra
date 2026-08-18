#!/bin/bash
set -e

# Create the workflow database (separate from n8n's main DB)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE n8n_workflows;
    GRANT ALL PRIVILEGES ON DATABASE n8n_workflows TO n8n;
EOSQL

echo "Database n8n_workflows created successfully"