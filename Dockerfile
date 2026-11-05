# =================================================================
# STAGE 1: BUILDER (Kompilasi BadVPN UDPGW)
# =================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    make \
    gcc \
    g++ \
    curl \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Download dan compile badvpn-udpgw dari release github
RUN curl -fsSL https://github.com/ambrop72/badvpn/archive/refs/tags/1.999.130.tar.gz | tar -xz \
    && cd badvpn-1.999.130 \
    && mkdir build && cd build \
    && cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 \
    && make badvpn-udpgw

# =================================================================
# STAGE 2: BUILD FRONTEND (React + Vite)
# =================================================================
FROM node:20-slim AS frontend

WORKDIR /web

COPY package.json package-lock.json* ./
RUN npm ci || npm install

COPY . .
RUN npm run build

# =================================================================
# STAGE 3: RUNTIME (Pondasi Utama Aplikasi & Network Services)
# =================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Node.js, Dropbear, Stunnel, jq, dan tools pendukung
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    dropbear \
    stunnel4 \
    openssl \
    ca-certificates \
    procps \
    net-tools \
    bash \
    jq \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Unduh utilitas Cloudflared Resmi
RUN curl -fsSL -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

# Salin binary badvpn-udpgw dari stage builder
COPY --from=builder /src/badvpn-1.999.130/build/udpgw/badvpn-udpgw /usr/local/bin/badvpn-udpgw
RUN chmod +x /usr/local/bin/badvpn-udpgw

# Atur Direktori Kerja Container
WORKDIR /app

# Salin package.json dan pasang dependensi NPM (untuk server.cjs)
COPY package.json package-lock.json* ./
RUN npm install --omit=dev || npm install

# =================================================================
# ✅ SALIN SEMUA ENTRYPOINT & SERVICE SCRIPT (CommonJS — .cjs)
# =================================================================
# server.cjs    -> UI + API + WebSocket gateway (port 8081)
# ws-proxy.cjs  -> SSH WebSocket proxy (port 8880)
# mux.cjs       -> TLS/WS traffic splitter (port 8881)
# start.sh      -> Entrypoint orchestrator
COPY server.cjs start.sh ws-proxy.cjs mux.cjs ./
RUN chmod +x start.sh

# Salin hasil build frontend (dist/) dari stage frontend
COPY --from=frontend /web/dist ./dist

# =================================================================
# PORTS
# =================================================================
# 8081 -> UI + API + Xray Gateway (server.cjs)
# 8880 -> WS-Proxy SSH Dropbear (ws-proxy.cjs)
# 8881 -> Mux TLS/WS splitter (mux.cjs)
# 8001 -> Xray internal inbound (VLESS/VMess/Trojan)
EXPOSE 8081 8880 8881

# Eksekusi utama saat container aktif (Berjalan penuh sebagai ROOT)
CMD ["./start.sh"]
