/**
 * Mock server that simulates antigravity_automation extension ports:
 *   HTTP  5000  POST /send_command  { text }
 *   WS    9812  broadcasts { content } after receiving a command
 */
const http = require('http');
const { WebSocketServer } = require('C:/Users/tianh/.antigravity-ide/extensions/joecodecreations.antigravity-automation-1.11.0/node_modules/ws');

const WS_PORT = 9812;
const HTTP_PORT = 5000;
const wss = new WebSocketServer({ port: WS_PORT });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

const broadcast = (msg) => {
  const payload = JSON.stringify({ content: msg });
  for (const c of clients) { try { c.send(payload); } catch (_) {} }
};

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/send_command') {
    let body = '';
    req.on('data', d => body += d);
    req.on('end', () => {
      let instruction = '';
      try { instruction = JSON.parse(body).text || ''; } catch (_) {}
      console.log(`[MOCK] Received instruction (${instruction.length} chars): ${instruction.slice(0, 80)}...`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'queued' }));
      // Simulate Antigravity executing and streaming response after 1.5s
      setTimeout(() => {
        const mockResult = `[Mock Antigravity Response]\nExecuted: ${instruction.slice(0, 100)}\nResult: Task completed successfully at ${new Date().toISOString()}\nFiles created: C:\\Users\\tianh\\tmp\\loop-verify.txt`;
        broadcast(mockResult);
        console.log(`[MOCK] Broadcasted WS response (${mockResult.length} chars)`);
      }, 1500);
    });
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(HTTP_PORT, () => {
  console.log(`[MOCK] HTTP  listening on port ${HTTP_PORT}`);
  console.log(`[MOCK] WS    listening on port ${WS_PORT}`);
  console.log('[MOCK] Ready. Press Ctrl+C to stop.');
});
