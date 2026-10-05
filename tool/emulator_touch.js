// Touches the running emulator the way fingers do, through its gRPC EmulatorController
// (sendTouch): two fingers at once, which adb and Maestro cannot do, and a swipe that starts
// slowly, as a finger does (`adb shell input swipe` jumps tens of pixels in its first move,
// which no finger does, and gestures that a finger wins can lose to it).
//
//   node tool/emulator_touch.js pinch <cx> <cy> <fromGap> <toGap> [steps] [ms]
//        two fingers side by side around (cx, cy), from <fromGap> to <toGap> pixels apart
//   node tool/emulator_touch.js swipe <x0> <y0> <x1> <y1> [steps] [ms]
//
// Coordinates are the device's pixels. The port and token come from the emulator's file in
// %LOCALAPPDATA%\Temp\avd\running, so only one emulator may be running.
const fs = require('fs');
const path = require('path');
const http2 = require('http2');

const dir = path.join(process.env.LOCALAPPDATA, 'Temp', 'avd', 'running');
const inis = fs.readdirSync(dir).filter((f) => /^pid_\d+\.ini$/.test(f));
if (inis.length !== 1) {
  console.error(`expected one running emulator, found ${inis.length}`);
  process.exit(1);
}
const text = fs.readFileSync(path.join(dir, inis[0]), 'utf8');
const port = /grpc\.port=(\d+)/.exec(text)[1];
const token = /grpc\.token=(\S+)/.exec(text)[1];

function varint(n) {
  const out = [];
  while (n > 127) {
    out.push((n & 127) | 128);
    n >>>= 7;
  }
  out.push(n);
  return out;
}

const field = (tag, n) => [tag << 3, ...varint(n)];

// TouchEvent { repeated Touch touches = 1 }, Touch { x = 1, y = 2, identifier = 3,
// pressure = 4 }; a pressure of 0 lifts the finger.
function touchEvent(fingers) {
  const body = [];
  for (const [x, y, id, pressure] of fingers) {
    const t = [
      ...field(1, Math.round(x)),
      ...field(2, Math.round(y)),
      ...field(3, id),
      ...field(4, pressure),
    ];
    body.push(0x0a, ...varint(t.length), ...t);
  }
  const frame = Buffer.alloc(5 + body.length);
  frame.writeUInt32BE(body.length, 1);
  Buffer.from(body).copy(frame, 5);
  return frame;
}

const client = http2.connect(`http://localhost:${port}`);

function send(fingers) {
  return new Promise((resolve, reject) => {
    const req = client.request({
      ':method': 'POST',
      ':path': '/android.emulation.control.EmulatorController/sendTouch',
      'content-type': 'application/grpc',
      te: 'trailers',
      authorization: `Bearer ${token}`,
    });
    let status;
    req.on('response', (h) => (status = h['grpc-status']));
    req.on('trailers', (h) => (status = h['grpc-status'] ?? status));
    req.on('end', () =>
      status && status !== '0' ? reject(new Error(`grpc ${status}`)) : resolve(),
    );
    req.on('error', reject);
    req.end(touchEvent(fingers));
    req.resume();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const down = 512;

async function pinch(cx, cy, from, to, steps = 12, ms = 400) {
  const at = (gap, pressure) => [
    [cx - gap / 2, cy, 0, pressure],
    [cx + gap / 2, cy, 1, pressure],
  ];
  await send(at(from, down));
  await sleep(60);
  for (let i = 1; i <= steps; i++) {
    await send(at(from + ((to - from) * i) / steps, down));
    await sleep(ms / steps);
  }
  await sleep(60);
  await send(at(to, 0));
}

async function swipe(x0, y0, x1, y1, steps = 20, ms = 250) {
  await send([[x0, y0, 0, down]]);
  await sleep(30);
  for (let i = 1; i <= steps; i++) {
    const t = (i / steps) ** 2;
    await send([[x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0, down]]);
    await sleep(ms / steps);
  }
  await send([[x1, y1, 0, 0]]);
}

const [command, ...rest] = process.argv.slice(2);
const args = rest.map(Number);
const run = { pinch, swipe }[command];
if (!run || args.length < 4 || args.some(Number.isNaN)) {
  console.error('usage: emulator_touch.js pinch|swipe <four numbers> [steps] [ms]');
  process.exit(1);
}
run(...args)
  .then(() => client.close())
  .catch((e) => {
    console.error(e.message);
    client.close();
    process.exit(1);
  });
