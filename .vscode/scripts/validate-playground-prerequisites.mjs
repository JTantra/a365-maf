#!/usr/bin/env node

import net from "node:net";

const minimumNodeMajor = 12;
const ports = [3978, 56150];

function validateNodeVersion() {
  const major = Number.parseInt(process.versions.node.split(".")[0] ?? "0", 10);
  if (Number.isNaN(major) || major < minimumNodeMajor) {
    throw new Error(
      `Node.js ${minimumNodeMajor}+ is required, but found ${process.version}.`
    );
  }

  console.log(`Node.js ${process.version} detected.`);
}

function checkPort(port) {
  return new Promise((resolve) => {
    const server = net.createServer();

    server.once("error", (error) => {
      resolve({
        port,
        available: false,
        message:
          error.code === "EADDRINUSE"
            ? `Port ${port} is already in use.`
            : `Unable to check port ${port}: ${error.message}`,
      });
    });

    server.once("listening", () => {
      server.close(() => {
        resolve({ port, available: true, message: `Port ${port} is available.` });
      });
    });

    server.listen({ host: "0.0.0.0", port });
  });
}

async function main() {
  validateNodeVersion();

  const results = await Promise.all(ports.map(checkPort));
  for (const result of results) {
    console.log(result.message);
  }

  const unavailable = results.filter((result) => !result.available);
  if (unavailable.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});