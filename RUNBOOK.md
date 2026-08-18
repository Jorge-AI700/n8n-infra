# Runbook — ISP bloquea Cloudflare → acceder a n8n vía WireGuard

**[Hermes] · 2026-08-15**

## Problema
El ISP de Jorge (Movistar/Telefónica, España) y su red universitaria bloquean
el rango de IP de Cloudflare `188.114.96.0/20`. Como `n8n.wizdom-ai.com` pasa por
Cloudflare Tunnel, ese bloqueo deja inaccesible tanto el web n8n como el endpoint
MCP (`/mcp-server/http`) que usa Claude Code para gestionar la instancia.
NO es problema de config ni del VPS; es bloqueo a nivel de red del ISP.

## Solución
Túnel **WireGuard** VPS ↔ laptop que va DIRECTO a la IP dedicada del VPS
(`46.224.67.47`), sin pasar por Cloudflare. Funciona desde cualquier red
(casa, universidad, etc.), no solo la actual.

## Estructura
| | |
|---|---|
| VPS | Hetzner Cloud (FSN1), Ubuntu 26.04, pub `46.224.67.47` |
| Server WG | `10.8.0.1/24`, UDP `51820` |
| Laptop peer | `10.8.0.2/24` |
| Split tunnel | `AllowedIPs = 10.8.0.0/24` (solo tráfico interno va por VPN) |
| n8n interno | `http://10.8.0.1:5678` (MCP: `/mcp-server/http`) |
| CF Tunnel | intacto en paralelo para uso público (loopback 127.0.0.1) |

## Armar servidor (VPS, una vez, root)
```bash
sudo apt-get install -y wireguard wireguard-tools
# /etc/wireguard/wg0.conf (server privkey, peer = laptop pubkey)
sudo systemctl enable --now wg-quick@wg0
sudo ufw allow 51820/udp
```
Config `/etc/wireguard/wg0.conf` (server):
```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIV>

[Peer]
PublicKey = <LAPTOP_PUB>
AllowedIPs = 10.8.0.2/32
PersistentKeepalive = 25
```

## Armar cliente (laptop Ubuntu)
```bash
sudo apt-get install -y wireguard wireguard-tools
sudo install -m 600 /dev/stdin /etc/wireguard/wg0.conf <<'EOF'
[Interface]
Address = 10.8.0.2/24
PrivateKey = <LAPTOP_PRIV>
DNS = none

[Peer]
PublicKey = <SERVER_PUB>
Endpoint = 46.224.67.47:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
EOF
sudo systemctl enable --now wg-quick@wg0
```

## Abrir n8n SOLO por el túnel (seguridad)
n8n docker escuchaba solo en `127.0.0.1:5678`. Se añadió bind `10.8.0.1:5678:5678`
en `~/n8n/docker-compose.yml` y `docker compose up -d n8n`.
Resultado: n8n en `10.8.0.1` (túnel) + `127.0.0.1` (CF Tunnel) — **NO** en la IP
pública `46.224.67.47`. A internet no hay listener → nada expuesto.

## MCP de Claude Code
Antes: `https://n8n.wizdom-ai.com/mcp-server/http` (bloqueado por ISP)
Ahora: `http://10.8.0.1:5678/mcp-server/http` (por túnel, mismo token)

## Cómo se diagnosticó (breve)
1. Descartado queue-mode / worker muerto: `EXECUTIONS_MODE=regular`, 1 proceso.
2. Webhook 404 previo = ya resuelto (path con UUID de más; url correcta
   `…/webhook/apex-whatsapp-inbound`).
3. MCP: instancia `/mcp` OK; el problema eran los paquetes.
4. `tcpdump` UDP 51820 en VPS (control positivo OK) → **cero paquetes del laptop** →
   caída ANTES del VPS.
5. SSH (TCP 22) sí llegaba → no es bloqueo total del IP → **Hetzner Cloud Firewall**
   no pasaba UDP 51820. Se añadió regla UDP en el panel → listo.

## Troubleshooting
- Sin handshake: `sudo wg show` en VPS; si `latest handshake` ausente/0 bytes →
  firewall (Hetzner panel o ufw) o `traceroute -U -p 51820 46.224.67.47` desde laptop.
- Reintentar conexión: `sudo wg-quick down wg0; sleep 2; sudo wg-quick up wg0`.

## Archivos en VPS
`~/wireguard-setup/keys.env`, `wg0.conf` (server), `jorge-laptop.conf` (cliente),
`bootstrap.sh`.

---

# Anexo — n8n: TLS en el túnel (browser) + layout de puertos (2026-08-15)

## Problema
n8n exige HTTPS (N8N_SECURE_COOKIE=true, default) para setear cookie de sesión.
Al acceder por el túnel WG en plain http (`http://10.8.0.1:5678`) n8n rechaza login:
"configured to use a secure cookie... insecure URL".

## Solución
**Caddy** (contenedor docker) termina TLS en `10.8.0.1:5678` (self-signed, `tls internal`)
y hace reverse_proxy a `127.0.0.1:5679`. n8n confía en `X-Forwarded-Proto: https`
vía `N8N_PROXY_HOPS=1`. **`N8N_SECURE_COOKIE` NO se tocó** (global segura intacta).

- n8n tunnel bind se movió de `10.8.0.1:5678` a loopback backend `127.0.0.1:5679`.
- MCP (usa token, no cookie → no necesita TLS): puerto plano solo-túnel `10.8.0.1:5679`.

## Layout de puertos (solo túnel + loopback)
| Interfaz | Quién | Uso | Proto |
|---|---|---|---|
| `10.8.0.1:5678` | Caddy(tls) → `127.0.0.1:5679` | browser login | HTTPS (self-signed) |
| `10.8.0.1:5679` | n8n directo | MCP Claude | plain (token) |
| `127.0.0.1:5678` | n8n directo | Cloudflare Tunnel | public https |
| `127.0.0.1:5679` | n8n directo | Caddy backend | plain |

## URLs finales
- Browser por túnel: `https://10.8.0.1:5678` (aceptar self-signed una vez).
- MCP Claude Code: `http://10.8.0.1:5679/mcp-server/http` (mismo token).
- Público: `https://n8n.wizdom-ai.com` (intacto).

## Archivos / cambios
- `~/wireguard-setup/Caddyfile` (site `https://10.8.0.1:5678 { bind 10.8.0.1; tls internal; reverse_proxy 127.0.0.1:5679 }`).
- Caddy contenedor: `caddy-n8n`, `--network host`, `--restart unless-stopped`, vols `caddy-n8n-data`/`caddy-n8n-config`.
- `~/n8n/docker-compose.yml`: ports `127.0.0.1:5678`, `127.0.0.1:5679`, `10.8.0.1:5679`; env `N8N_PROXY_HOPS: '1'`.
- `bind` es clave: sin él Caddy bindea `0.0.0.0:5678` y choca con n8n loopback 5678.