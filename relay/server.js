// Peekaboo House relay: puts players in rooms by 4-letter code and forwards their messages.
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8787;
const LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ';
const MAX_PLAYERS = 4;
const rooms = new Map();

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'content-type': 'text/plain' });
  res.end(`Peekaboo House relay is running. Rooms open: ${rooms.size}\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 });

function newCode() {
  let c;
  do { c = Array.from({ length: 4 }, () => LETTERS[Math.random() * LETTERS.length | 0]).join(''); } while (rooms.has(c));
  return c;
}
const send = (ws, m) => { if (ws.readyState === 1) ws.send(JSON.stringify(m)); };
const list = room => [...room.players].map(([id, p]) => ({ id, name: p.name, color: p.color }));
function bcast(room, m, except) {
  const out = JSON.stringify(m);
  const isState = m.t === 'st';
  for (const [id, p] of room.players) {
    if (id === except || p.ws.readyState !== 1) continue;
    // a player who has fallen behind only needs the newest positions, not a backlog
    if (isState && p.ws.bufferedAmount > 32 * 1024) continue;
    p.ws.send(out);
  }
}

wss.on('connection', (ws, req) => {
  // send each small message straight away (no Nagle bundling) - keeps the ping low
  if (req.socket && req.socket.setNoDelay) req.socket.setNoDelay(true);
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  let room = null, id = 0;

  ws.on('message', data => {
    let m;
    try { m = JSON.parse(data.toString()); } catch { return; }
    if (!m || typeof m.t !== 'string') return;

    if (!room) {
      if (m.t === 'create') {
        room = { code: newCode(), players: new Map(), host: 0, nextId: 1 };
        rooms.set(room.code, room);
      } else if (m.t === 'join') {
        const r = rooms.get(String(m.room || '').toUpperCase().trim());
        if (!r) return send(ws, { t: 'error', msg: 'No room with that code. Check the letters and try again.' });
        if (r.players.size >= MAX_PLAYERS) return send(ws, { t: 'error', msg: 'That room is full (4 players max).' });
        room = r;
      } else return;
      id = room.nextId++;
      const name = String(m.name || 'Player').slice(0, 14);
      const color = Math.max(0, Math.min(15, Number(m.color) | 0));
      room.players.set(id, { ws, name, color });
      if (!room.host) room.host = id;
      send(ws, { t: 'welcome', id, room: room.code, host: room.host, players: list(room) });
      bcast(room, { t: 'peer_join', id, name, color }, id);
      return;
    }

    if (m.t === 'ping') return send(ws, { t: 'pong' });
    m.from = id;
    if (m.to != null) {
      const p = room.players.get(Number(m.to));
      if (p) send(p.ws, m);
      return;
    }
    bcast(room, m, id);
  });

  ws.on('close', () => {
    if (!room) return;
    room.players.delete(id);
    if (room.players.size === 0) { rooms.delete(room.code); return; }
    bcast(room, { t: 'peer_leave', id });
    if (room.host === id) {
      room.host = Math.min(...room.players.keys());
      bcast(room, { t: 'host', id: room.host });
    }
  });
});

setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 25000);

server.listen(PORT, '0.0.0.0', () => console.log(`PekaBoo relay listening on ${PORT}`));
