"""copyEzz: atajo → captura de pantalla → modelo de visión → respuesta en el <title> de una pestaña localhost.

Uso: uv run copyezz.py [--backend claude-code|api|ollama] [--model M] [--port 8765] [--no-open]
"""

import argparse
import json
import queue
import subprocess
import tempfile
import threading
import time
import webbrowser
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import backends

ROOT = Path(__file__).parent
INDEX = ROOT.parent / "Resources" / "index.html"  # compartido con la app nativa
HISTORY = ROOT / "history.jsonl"
MAX_EDGE = 1568  # lado máximo que aprovechan los modelos de visión; más grande solo cuesta tokens


class State:
    def __init__(self, backend: str, model: str):
        self.lock = threading.Lock()
        self.backend = backend
        self.model = model
        self.seq = 0
        self.busy = False
        self.results: deque[dict] = deque(maxlen=50)
        self.subscribers: set[queue.Queue] = set()

    def config(self) -> dict:
        return {
            "type": "config",
            "backend": self.backend,
            "model": self.model,
            "backends": {name: b.default_model for name, b in backends.BACKENDS.items()},
        }

    def subscribe(self) -> tuple[queue.Queue, dict]:
        q: queue.Queue = queue.Queue()
        with self.lock:
            self.subscribers.add(q)
            hello = {**self.config(), "type": "hello", "busy": self.busy, "results": list(self.results)}
        return q, hello

    def unsubscribe(self, q: queue.Queue) -> None:
        with self.lock:
            self.subscribers.discard(q)

    def publish(self, event: dict) -> None:
        with self.lock:
            subscribers = list(self.subscribers)
        for q in subscribers:
            q.put(event)


def capture_screen() -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp, "shot.png")
        try:
            subprocess.run(["screencapture", "-x", "-m", "-t", "png", str(path)], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            raise RuntimeError("screencapture falló (¿la terminal tiene permiso de Grabación de pantalla?)") from None
        return path.read_bytes()


def downscale(png: bytes) -> bytes:
    if not png.startswith(b"\x89PNG"):
        raise ValueError("la imagen recibida no es PNG")
    width, height = int.from_bytes(png[16:20], "big"), int.from_bytes(png[20:24], "big")
    if max(width, height) <= MAX_EDGE:
        return png
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp, "in.png"), Path(tmp, "out.png")
        src.write_bytes(png)
        subprocess.run(["sips", "-Z", str(MAX_EDGE), str(src), "--out", str(dst)], check=True, capture_output=True)
        return dst.read_bytes()


def solve(state: State, png: bytes | None) -> None:
    with state.lock:
        state.seq += 1
        request_id, backend, model = state.seq, state.backend, state.model
        state.busy = True
    state.publish({"type": "thinking", "id": request_id})

    started = time.monotonic()
    event = {"id": request_id, "ts": time.time(), "backend": backend, "model": model}
    try:
        image = downscale(png or capture_screen())
        text = backends.BACKENDS[backend].solve(image, model).strip()
        answer, _, detail = text.partition("\n")
        event.update(type="answer", answer=answer.strip() or "(vacío)", detail=detail.strip())
    except Exception as e:
        event.update(type="error", error=str(e) or type(e).__name__)
    event["ms"] = round((time.monotonic() - started) * 1000)

    with HISTORY.open("a") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")
    with state.lock:
        latest = request_id == state.seq
        if latest:
            state.busy = False
            state.results.append(event)
    if latest:  # si no, una captura más nueva ya la reemplazó
        state.publish(event)
    print(f"[{backend}/{model}] {event['ms']} ms → {event.get('answer') or '⚠ ' + event['error']}", flush=True)


class Handler(BaseHTTPRequestHandler):
    state: State
    port: int

    def _allowed(self) -> bool:
        # Solo el propio localhost: bloquea DNS rebinding (Host) y POSTs de otras páginas (Origin).
        hosts = {f"127.0.0.1:{self.port}", f"localhost:{self.port}"}
        origin = self.headers.get("Origin")
        if self.headers.get("Host") not in hosts or (origin and origin.removeprefix("http://") not in hosts):
            self._send(403, b"forbidden")
            return False
        return True

    def _send(self, status: int, body: bytes, content_type: str = "text/plain; charset=utf-8") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if not self._allowed():
            return
        if self.path == "/":
            self._send(200, INDEX.read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/events":
            self._stream_events()
        else:
            self._send(404, b"not found")

    def do_POST(self) -> None:
        if not self._allowed():
            return
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/solve":
            threading.Thread(target=solve, args=(self.state, body or None), daemon=True).start()
            self._send(202, b"ok")
        elif self.path == "/config":
            self._update_config(body)
        else:
            self._send(404, b"not found")

    def _update_config(self, body: bytes) -> None:
        try:
            data = json.loads(body)
            backend = data["backend"]
            if backend not in backends.BACKENDS:
                raise ValueError(backend)
        except (ValueError, KeyError, TypeError):
            self._send(400, b"backend invalido")
            return
        with self.state.lock:
            self.state.backend = backend
            self.state.model = (data.get("model") or "").strip() or backends.BACKENDS[backend].default_model
            config = self.state.config()
        self.state.publish(config)
        self._send(200, json.dumps(config).encode(), "application/json")

    def _stream_events(self) -> None:
        q, hello = self.state.subscribe()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            self._write_event(hello)
            while True:
                try:
                    self._write_event(q.get(timeout=15))
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            self.state.unsubscribe(q)

    def _write_event(self, event: dict) -> None:
        self.wfile.write(f"data: {json.dumps(event, ensure_ascii=False)}\n\n".encode())
        self.wfile.flush()

    def log_message(self, format: str, *args) -> None:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Captura → modelo de visión → respuesta en el título de la pestaña.")
    parser.add_argument("--backend", choices=backends.BACKENDS, default="claude-code")
    parser.add_argument("--model", help="por defecto: sonnet / claude-opus-5-5 / qwen2.5vl:7b según el motor")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-open", action="store_true", help="no abrir el navegador al iniciar")
    args = parser.parse_args()

    Handler.state = State(args.backend, args.model or backends.BACKENDS[args.backend].default_model)
    Handler.port = args.port
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}"
    print(f"copyEzz en {url} · motor {Handler.state.backend} ({Handler.state.model}) · Ctrl+C para salir", flush=True)
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
