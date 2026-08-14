// Send a task to the Antigravity agent panel via CDP native input events.
// Usage: node cdp-send.js "<task text>"
const WebSocket = require('C:/Users/tianh/.antigravity-ide/extensions/joecodecreations.antigravity-automation-1.11.0/node_modules/ws');
const http = require('http');

const text = process.argv[2];
if (!text) { console.error('no text'); process.exit(1); }

http.get('http://127.0.0.1:58790/json/list', res => {
  let d = '';
  res.on('data', c => d += c);
  res.on('end', () => {
    const page = JSON.parse(d).find(t => t.type === 'page');
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    let id = 0;
    const pending = {};
    const call = (method, params) => new Promise(r => { id++; pending[id] = r; ws.send(JSON.stringify({ id, method, params })); });
    ws.on('message', m => { const msg = JSON.parse(m); if (msg.id && pending[msg.id]) { pending[msg.id](msg.result); delete pending[msg.id]; } });
    ws.on('open', async () => {
      // focus the message input
      const f = await call('Runtime.evaluate', { expression: "(function(){const el=[...document.querySelectorAll('[contenteditable=true]')].find(e=>e.className.includes('cursor-text'));if(!el)return 'NO INPUT';el.focus();return 'focused'})()", returnByValue: true });
      console.log('focus:', JSON.stringify(f.result.value));
      if (f.result.value !== 'focused') { process.exit(1); }
      await call('Input.insertText', { text });
      await new Promise(r => setTimeout(r, 500));
      const chk = await call('Runtime.evaluate', { expression: "[...document.querySelectorAll('[contenteditable=true]')].find(e=>e.className.includes('cursor-text')).textContent.slice(0,100)", returnByValue: true });
      console.log('content:', JSON.stringify(chk.result.value));
      // press Enter to send
      await call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
      await call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
      await new Promise(r => setTimeout(r, 800));
      const after = await call('Runtime.evaluate', { expression: "[...document.querySelectorAll('[contenteditable=true]')].find(e=>e.className.includes('cursor-text')).textContent.length", returnByValue: true });
      console.log('input length after Enter:', after.result.value, '(0 = sent)');
      process.exit(0);
    });
    ws.on('error', e => { console.error('WS error:', e.message); process.exit(1); });
    setTimeout(() => { console.error('timeout'); process.exit(1); }, 30000);
  });
}).on('error', e => { console.error(e.message); process.exit(1); });
