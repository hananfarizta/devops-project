const express = require("express");

// Konfigurasi aplikasi dari environment variables
const PORT = process.env.PORT || 3000;
const APP_MESSAGE = process.env.APP_MESSAGE || "Hello from HeyPico.ai";
const LOG_LEVEL = process.env.LOG_LEVEL || "info";

const app = express();

// Middleware sederhana untuk logging
app.use((req, res, next) => {
  if (LOG_LEVEL === "debug") {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  }
  next();
});

// Endpoint utama
app.get("/", (req, res) => {
  res.status(200).send(APP_MESSAGE);
});

// Endpoint health check untuk Kubernetes probes
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", timestamp: new Date().toISOString() });
});

// Start server
const server = app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
  console.log(`App message: "${APP_MESSAGE}"`);
  console.log(`Log level: "${LOG_LEVEL}"`);
});

// Handle shutdown gracefully
process.on("SIGTERM", () => {
  console.log("SIGTERM signal received: closing HTTP server");
  server.close(() => {
    console.log("HTTP server closed");
  });
});
