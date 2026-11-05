# Deployment Guide - SSH & VPN Panel (React + Material 3)

## Arsitektur

Aplikasi ini terdiri dari 3 bagian:

1. **Frontend** (React + Vite + Tailwind CSS dengan Material Design 3) — di-build menjadi file statis di folder `dist/`
2. **Backend** (`server.js`) — Node.js HTTP server yang melayani:
   - API endpoints (`/api/*`, `/__info`)
   - Static files dari `dist/` (frontend React)
   - WebSocket forwarding untuk VLESS/VMess/Trojan dan SSH
3. **Docker** (`Dockerfile` + `start.sh`) — Container yang menginstall Dropbear, BadVPN UDPGW, Cloudflared, dan menjalankan `server.js`

## Cara Setting Docker

### 1. Build & Run dengan Docker

```bash
# Build image
docker build -t ssh-vpn-panel .

# Run container
docker run -d \
  --name ssh-panel \
  --cap-add=NET_ADMIN \
  --privileged \
  -p 8081:8081 \
  -e UUID="1f37ac4f-fdd0-49df-9406-1eda70a1d512" \
  -e PORT=8081 \
  -e NAME="ddfathu" \
  -e CFPORT=443 \
  -e ENABLE_BBR=true \
  -e SSH_PORT=22 \
  -e UDPGW_PORT=7300 \
  ssh-vpn-panel
```

### 2. Environment Variables

| Variable | Default | Keterangan |
|----------|---------|------------|
| `PORT` | `8081` | Port HTTP server |
| `UUID` | `1f37ac4f-...` | UUID untuk V2Ray/Xray |
| `NAME` | `ddfathu` | Nama node untuk config |
| `CFPORT` | `443` | Port Cloudflare |
| `CFIP` | `104.17.3.81` | Cloudflare Clean IP |
| `ENABLE_BBR` | `true` | Enable TCP BBR |
| `SSH_PORT` | `22` | Port Dropbear SSH |
| `UDPGW_PORT` | `7300` | Port UDPGW |
| `RAILWAY_PUBLIC_DOMAIN` | - | Domain Railway Reality |
| `RAILWAY_TCP_PROXY_DOMAIN` | - | Domain TCP Proxy |
| `RAILWAY_TCP_PROXY_PORT` | - | Port TCP Proxy |
| `SNI` | - | SNI domain alternatif |
| `SUB_PATH` | `sub` | Path untuk subscription |
| `ADMIN_PASSWORD` | - | Password admin (opsional, bisa set via UI) |

### 3. Deploy ke Railway

1. Push project ke GitHub
2. Buat project baru di Railway, pilih repo
3. Railway akan mendeteksi `Dockerfile` secara otomatis
4. Set environment variables di Railway dashboard
5. Railway akan build dan deploy otomatis

### 4. Deploy ke VPS / Docker Compose

```yaml
version: '3.8'
services:
  ssh-panel:
    build: .
    container_name: ssh-panel
    privileged: true
    cap_add:
      - NET_ADMIN
    ports:
      - "8081:8081"
    environment:
      - UUID=1f37ac4f-fdd0-49df-9406-1eda70a1d512
      - PORT=8081
      - NAME=ddfathu
      - ENABLE_BBR=true
      - SSH_PORT=22
      - UDPGW_PORT=7300
    restart: unless-stopped
```

```bash
docker-compose up -d
```

## Cara Setting server.js

`server.js` adalah backend Node.js yang:

1. **Melayani frontend React** — Membaca file statis dari folder `dist/` (hasil `npm run build`) dan mengirimkannya ke browser. Semua route yang bukan `/api/*` akan fallback ke `index.html` (SPA routing).

2. **API endpoints** — Menangani semua endpoint seperti `/api/stats`, `/api/add`, `/api/delete`, `/api/login`, `/api/set-network`, dll.

3. **WebSocket forwarding** — Meneruskan koneksi WebSocket ke Xray (port 8001) untuk VLESS/VMess/Trojan, dan ke Dropbear untuk SSH WebSocket.

4. **Auto-start services** — Saat server start, otomatis:
   - Generate Xray config
   - Download dan jalankan Xray binary
   - Jalankan Cloudflared tunnel
   - Extract domain dari log tunnel

### Development (Local)

```bash
# Install dependencies
npm install

# Build frontend
npm run build

# Start server
node server.js
```

### Build Frontend Saja

```bash
npm run build
# Hasil ada di dist/
```

## Dockerfile Penjelasan

Dockerfile menggunakan **multi-stage build** (3 stage):

### Stage 1: Builder (BadVPN UDPGW)
- Mengkompilasi `badvpn-udpgw` dari source code untuk UDP forwarding
- Menggunakan Ubuntu 22.04 + cmake + gcc

### Stage 2: Frontend (React)
- Menggunakan `node:20-slim` image
- Install dependencies dan build React app dengan Vite
- Output: folder `dist/` dengan HTML, CSS, JS yang sudah di-optimize

### Stage 3: Runtime
- Ubuntu 22.04 dengan Node.js 20, Dropbear, Stunnel, Cloudflared
- Copy binary UDPGW dari Stage 1
- Copy `dist/` dari Stage 2
- Copy `server.js` dan `start.sh`
- Jalankan `start.sh` yang memulai Dropbear + UDPGW + Node.js server

## Keamanan

- Admin password disimpan di `/tmp/admin_pass.txt` di dalam container
- Password bisa di-set pertama kali via UI ("SETUP PASS" button)
- Semua operasi sensitif (delete user, change settings) memerlukan admin login
- RLS / access control via token-based auth di server.js
