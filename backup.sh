#!/usr/bin/env bash
# Verus n8n — weekly backup. Postgres dump + n8n_data volume. Keep 4.
set -euo pipefail
BACKUP_DIR="/home/jorge/n8n/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 1) Postgres dump (n8n's workflows, credentials, history)
docker exec n8n-postgres-1 pg_dump -U n8n -d n8n_main -Fc \
  > "$BACKUP_DIR/n8n_pg_$STAMP.dump" 2>"$BACKUP_DIR/err_$STAMP.log" \
  || { echo "PG backup FAILED: $(tail -1 "$BACKUP_DIR/err_$STAMP.log")"; exit 1; }

# 2) n8n_data volume (files/uploads)
docker run --rm -v n8n_data:/data -v "$BACKUP_DIR":/backup alpine:3 \
  tar czf /backup/n8n_data_$STAMP.tar.gz -C /data . 2>/dev/null

# 3) retention — keep newest 4 of each
ls -1t "$BACKUP_DIR"/n8n_pg_*.dump 2>/dev/null | tail -n +5 | xargs -r rm -f
ls -1t "$BACKUP_DIR"/n8n_data_*.tar.gz 2>/dev/null | tail -n +5 | xargs -r rm -f
ls -1t "$BACKUP_DIR"/err_*.log 2>/dev/null | tail -n +5 | xargs -r rm -f

echo "backup OK $STAMP" >> "$BACKUP_DIR/STATUS.log"