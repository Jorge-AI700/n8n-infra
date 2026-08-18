# Verus n8n — self-hosted deployment (reproducible)

Plantilla para levantar tu n8n de producción (single-instance, prod-light).
Base real: VPS Hetzner Cloud, Ubuntu 26.04, Docker + docker compose.

## Stack
n8n (`n8nio/n8n:2.34.6` pinneado) + PostgreSQL 16 + Redis 7 + task-runners.
Expuesto: Cloudflare Tunnel (público) + WireGuard privado + Caddy TLS (browser priv).

## Archivos
| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Servicios n8n + postgres + redis + task-runners |
| `.env.example` | Plantilla de variables (copiar a `.env`, NUNCA commit `.env`) |
| `init-db.sh` | Init de la base al primer arranque |
| `Caddyfile` | TLS self-signed en el túnel privado (`10.8.0.1:5678`) |
| `backup.sh` | Backup semanal Postgres + n8n_data (retención 4) |
| `RUNBOOK.md` | Bloqueo ISP→Cloudflare y WireGuard (contexto) |
```

## Deploy en un VPS nuevo
```bash
git clone <repo> n8n && cd n8n
cp .env.example .env        # llená valores reales
# colocar binarios ffmpeg/ffprobe en ./ffmpeg ./ffprobe (o quitar sus mounts)
docker compose up -d
```
n8n queda en `127.0.0.1:5678`. Suficiente para acceso local/por túnel vía WG.
Para público: Cloudflare Tunnel apunta `n8n.wizdom-ai.com` → `127.0.0.1:5678`.

## Seguridad / topología
- **Editor de n8n = PRIVADO** (solo túnel WireGuard / loopback). NO se expone público.
- Público vía Tunnel: sólo webhooks (`/webhook/*`) + `/healthz`. Resto → 403. Ver `~/.cloudflared/config.yml`.
- VPN: WireGuard VPS↔laptop, UDP 51820, n8n también en `10.8.0.1:5679` (MCP plain, token).
- JAMÁS commitear `.env` (secrets). `N8N_ENCRYPTION_KEY` fija desde el primer boot.

## Límites conocidos (prod-light, NO enterprise)
- **Single instance**, `EXECUTIONS_MODE=regular` — sin HA/failover. OK para pocos clientes.
- `n8n-runners-custom:2.30.5` es **imagen local** (no está en registry) — hay que
  rebuild/bajar la official `n8nio/n8n-task-runners:<v>` en otro host.
- Backups locales en `./backups` (mejor un destino offsite para DR real).
- Monitor externo recomendado (UptimeRobot) + watchdog a Telegram ya configurado vía cron.

## Puertos
| Interfaz | Quién | Uso |
|---|---|---|
| `10.8.0.1:5678` | Caddy(tls→127.0.0.1:5679) | browser login priv (HTTPS self-signed) |
| `10.8.0.1:5679` | n8n directo | MCP (token) |
| `127.0.0.1:5678` | n8n directo | Cloudflare Tunnel (público webhooks) |
| `127.0.0.1:5679` | n8n directo | Caddy backend |