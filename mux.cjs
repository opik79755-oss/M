#!/usr/bin/env node
"use strict";

/**
 * TCP Multiplexer sederhana ala sslh (versi Node.js / CommonJS).
 *
 * Mendengarkan di SATU port publik, lalu mengintip beberapa byte pertama
 * dari koneksi masuk untuk menentukan protokolnya:
 *
 *   - Byte pertama 0x16 (TLS handshake record)      -> diteruskan ke Stunnel (SSL)
 *   - Selain itu (dianggap teks/HTTP-WS handshake)  -> diteruskan ke ws-proxy (WS)
 *
 * Berguna untuk platform seperti Railway yang cuma menyediakan SATU
 * TCP Proxy publik per service, sehingga SSH-SSL dan SSH-WS tetap bisa
 * diakses lewat port publik yang sama.
 */

const net = require("net");

const LISTEN_HOST = process.env.MAIN_MUX_LISTEN_HOST || "0.0.0.0";
const LISTEN_PORT = parseInt(
  process.env.MAIN_MUX_PORT || process.env.PORT || "443",
  10
);

const SSL_TARGET_HOST = process.env.SSL_TARGET_HOST || "127.0.0.1";
const SSL_TARGET_PORT = parseInt(
  process.env.SSL_TARGET_PORT || "2443",
  10
); // stunnel internal

const WS_TARGET_HOST = process.env.WS_MUX_TARGET_HOST || "127.0.0.1";
const WS_TARGET_PORT = parseInt(
  process.env.WS_MUX_TARGET_PORT || "8880",
  10
); // ws-proxy internal

const TLS_HANDSHAKE_BYTE = 0x16;

function log(level, msg) {
  const ts = new Date().toISOString();
  console.log(`[mux] ${ts} ${level} ${msg}`);
}

const server = net.createServer((socket) => {
  const peer = `${socket.remoteAddress}:${socket.remotePort}`;
  let backend = null;

  socket.on("error", (err) => {
    log("DEBUG", `Socket error ${peer}: ${err.message}`);
  });

  // Intip chunk pertama tanpa membuang data (chunk tetap kita simpan & teruskan)
  socket.once("data", (firstChunk) => {
    // Hentikan sementara agar sisa data yang datang tidak hilang sebelum pipe dipasang
    socket.pause();

    if (!firstChunk || firstChunk.length === 0) {
      socket.destroy();
      return;
    }

    const firstByte = firstChunk[0];
    let targetHost, targetPort, label;

    if (firstByte === TLS_HANDSHAKE_BYTE) {
      targetHost = SSL_TARGET_HOST;
      targetPort = SSL_TARGET_PORT;
      label = "SSL/stunnel";
    } else {
      targetHost = WS_TARGET_HOST;
      targetPort = WS_TARGET_PORT;
      label = "WS";
    }

    log(
      "INFO",
      `Koneksi ${peer} dikenali sebagai ${label} -> ${targetHost}:${targetPort}`
    );

    backend = net.connect({ host: targetHost, port: targetPort });
    let connected = false;

    backend.once("connect", () => {
      connected = true;

      // Kirim dulu byte/chunk pertama yang sudah kita intip
      backend.write(firstChunk);

      // Baru relay dua arah (pipe otomatis menangani backpressure)
      socket.pipe(backend);
      backend.pipe(socket);

      // Lanjutkan aliran data sisa dari socket
      socket.resume();
    });

    backend.on("error", (err) => {
      log(
        "ERROR",
        `Gagal konek ke backend ${label} -> ${targetHost}:${targetPort} : ${err.message}`
      );
      if (!connected) {
        socket.destroy();
      }
    });

    backend.on("close", () => {
      socket.destroy();
    });
  });

  socket.on("close", () => {
    if (backend) backend.destroy();
  });
});

server.on("error", (err) => {
  log("ERROR", `Server error: ${err.message}`);
  process.exit(1);
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  log(
    "INFO",
    `Mux jalan di ${LISTEN_HOST}:${LISTEN_PORT} -> ` +
      `SSL:${SSL_TARGET_HOST}:${SSL_TARGET_PORT} | ` +
      `WS:${WS_TARGET_HOST}:${WS_TARGET_PORT}`
  );
});

function shutdown(signal) {
  log("INFO", `Menerima ${signal}, menutup server...`);
  server.close(() => process.exit(0));
  // Paksa keluar setelah 3 detik bila koneksi menggantung
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
