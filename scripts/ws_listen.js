const WebSocket = require('C:/Users/tianh/.antigravity-ide/extensions/joecodecreations.antigravity-automation-1.11.0/node_modules/ws');
const ws = new WebSocket('ws://localhost:9812');
let timer = null;
let lastContent = '';
let received = false;

ws.on('open', () => {
  // Connected successfully
});

ws.on('message', (data) => {
  try {
    const msg = JSON.parse(data.toString());
    if (msg.content) {
      lastContent = msg.content;
      received = true;
      // Reset timer on message. If no new message in 10 seconds, assume agent finished response.
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        console.log(lastContent);
        process.exit(0);
      }, 10000);
    }
  } catch (err) {
    // Ignore JSON parsing errors
  }
});

ws.on('error', (err) => {
  console.error("WS_ERROR: " + err.message);
  process.exit(1);
});

// Safeguard total timeout: 180 seconds
setTimeout(() => {
  if (received) {
    console.log(lastContent);
    process.exit(0);
  } else {
    console.log("TIMEOUT: No message received from WebSocket.");
    process.exit(1);
  }
}, 180000);
