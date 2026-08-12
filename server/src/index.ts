import 'dotenv/config';
import express from 'express';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { api } from './routes.js';

const app = express();
app.use('/api', api);

// In production the server also serves the built frontend, so other devices
// on the network only need a browser pointed at this machine.
const clientDist = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'client',
  'dist'
);
if (fs.existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get('*', (req, res) => {
    if (req.path.startsWith('/api')) {
      res.status(404).json({ error: 'Unknown API route' });
      return;
    }
    res.sendFile(path.join(clientDist, 'index.html'));
  });
}

const port = Number(process.env.PORT) || 3000;
const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Server running on http://localhost:${port}`);
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const addr of addrs ?? []) {
      if (addr.family === 'IPv4' && !addr.internal) {
        console.log(`  From other devices on your network: http://${addr.address}:${port}`);
      }
    }
  }
  if (!process.env.FLEX_TOKEN || !process.env.FLEX_QUERY_ID) {
    console.warn(
      '\n⚠ Not connected to IBKR yet: copy server/.env.example to server/.env and fill in FLEX_TOKEN and FLEX_QUERY_ID (see README).'
    );
  }
});

server.on('error', (err: NodeJS.ErrnoException) => {
  if (err.code === 'EADDRINUSE') {
    console.error(
      `\n✗ Port ${port} is already taken — the app is probably already running.\n` +
        `  Check http://localhost:${port} in your browser. To stop the running copy: lsof -ti :${port} | xargs kill`
    );
    process.exit(1);
  }
  throw err;
});
