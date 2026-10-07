// Verifica de punta a punta que el título de la pestaña cambie: abre la página en Chrome headless
// (protocolo DevTools), envía un PNG a /solve y muestra document.title antes, durante y después.
// Uso: node scripts/title-check.mjs [png] [url]
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const png = process.argv[2] ?? "samples/quiz-sample.png";
const url = process.argv[3] ?? "http://127.0.0.1:8765";
const profile = mkdtempSync(join(tmpdir(), "copyezz-cdp-"));
const port = 9333;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const chrome = spawn(
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ["--headless=new", "--disable-gpu", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, "about:blank"],
  { stdio: "ignore" },
);

try {
  let targets;
  for (let i = 0; i < 40 && !targets; i++) {
    await sleep(250);
    targets = await fetch(`http://127.0.0.1:${port}/json`).then((r) => r.json()).catch(() => null);
  }
  const socket = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await new Promise((resolve) => (socket.onopen = resolve));
  let nextId = 0;
  const pending = new Map();
  socket.onmessage = (message) => {
    const data = JSON.parse(message.data);
    pending.get(data.id)?.(data.result);
  };
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      pending.set(++nextId, resolve);
      socket.send(JSON.stringify({ id: nextId, method, params }));
    });
  const title = async () =>
    (await send("Runtime.evaluate", {
      expression: "document.title + '  |  ' + document.getElementById('status').textContent",
    })).result.value;

  await send("Page.navigate", { url });
  await sleep(1500);
  console.log("al cargar:    ", await title());

  await fetch(`${url}/solve`, { method: "POST", headers: { "Content-Type": "image/png" }, body: readFileSync(png) });
  await sleep(500);
  console.log("tras disparar:", await title());

  for (let i = 1; i <= 60; i++) {
    await sleep(1000);
    const current = await title();
    if (!current.startsWith("…")) {
      console.log(`tras ${i} s:`.padEnd(14), current);
      break;
    }
  }
  socket.close();
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
