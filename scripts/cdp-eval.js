// Evaluate a JS expression in the Antigravity app page via CDP.
// Usage: node cdp-eval.js "<expression>"
const WebSocket = require('C:/Users/tianh/.antigravity-ide/extensions/joecodecreations.antigravity-automation-1.11.0/node_modules/ws');
const http = require('http');

const expr = process.argv[2];
if (!expr) { console.error('no expression'); process.exit(1); }

http.get('http://127.0.0.1:58790/json/list', res => {
  let d = '';
  res.on('data', c => d += c);
  res.on('end', () => {
    const targets = JSON.parse(d);
    const page = targets.find(t => t.type === 'page');
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    ws.on('open', () => {
      ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true, awaitPromise: true } }));
    });
    ws.on('message', m => {
      const msg = JSON.parse(m);
      if (msg.id === 1) {
        console.log(JSON.stringify(msg.result, null, 2));
        ws.close();
        process.exit(0);
      }
    });
    ws.on('error', e => { console.error('WS error:', e.message); process.exit(1); });
    setTimeout(() => { console.error('timeout'); process.exit(1); }, 30000);
  });
}).on('error', e => { console.error(e.message); process.exit(1); });
