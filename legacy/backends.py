"""Motores de visión: cada uno recibe el PNG de la captura y devuelve el texto del modelo."""

import base64
import json
import subprocess
import tempfile
import urllib.error
import urllib.request
from typing import Callable, NamedTuple

PROMPT = """\
Recibes una captura de pantalla completa. En algún lugar hay una pregunta de examen o quiz \
(opción múltiple, verdadero/falso o respuesta corta). Ignora el resto de la pantalla \
(pestañas, menús, temporizadores, botones).

Responde en exactamente dos líneas, sin markdown:
Línea 1: la respuesta correcta con el formato "<letra>) <texto de la opción>", por ejemplo "b) CHARTOROWID". \
Si hay varias correctas: "a) X, c) Y". Si es verdadero/falso: "Verdadero" o "Falso". \
Si es de respuesta corta: la respuesta en pocas palabras.
Línea 2: la justificación en una sola frase.
Si no hay ninguna pregunta visible, responde solo: SIN PREGUNTA"""

USER_TEXT = "Responde la pregunta de esta captura."


def _image_block(png: bytes) -> dict:
    data = base64.standard_b64encode(png).decode()
    return {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data}}


def claude_code(png: bytes, model: str) -> str:
    """Claude Code headless: usa la suscripción de `claude`, sin API key."""
    message = {
        "type": "user",
        "message": {"role": "user", "content": [_image_block(png), {"type": "text", "text": USER_TEXT}]},
    }
    command = [
        "claude", "-p",
        "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--model", model,
        "--system-prompt", PROMPT,
        # Sin herramientas, MCP, sesión guardada ni hooks: solo una respuesta, y arranque más rápido.
        "--tools", "", "--strict-mcp-config", "--no-session-persistence", "--setting-sources", "",
    ]
    try:
        proc = subprocess.run(
            command, input=json.dumps(message) + "\n", capture_output=True, text=True,
            timeout=120, cwd=tempfile.gettempdir(),
        )
    except FileNotFoundError:
        raise RuntimeError("no se encontró `claude` en el PATH") from None
    except subprocess.TimeoutExpired:
        raise RuntimeError("claude tardó más de 120 s") from None

    for line in reversed(proc.stdout.splitlines()):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "result":
            if event.get("is_error"):
                raise RuntimeError(event.get("result") or "claude devolvió un error")
            return event["result"]
    raise RuntimeError(proc.stderr.strip()[-300:] or f"claude salió con código {proc.returncode}")


def api(png: bytes, model: str) -> str:
    """API de Anthropic directa: requiere ANTHROPIC_API_KEY."""
    import anthropic  # solo lo necesita este motor

    # Haiku 4.5 no acepta `effort` ni los fallbacks de servidor.
    extra = {} if "haiku" in model else {
        "output_config": {"effort": "low"},
        "betas": ["server-side-fallback-2026-07-01"],
        "fallbacks": "default",
    }
    try:
        response = anthropic.Anthropic().beta.messages.create(
            model=model,
            max_tokens=4096,
            system=PROMPT,
            messages=[{"role": "user", "content": [_image_block(png), {"type": "text", "text": USER_TEXT}]}],
            **extra,
        )
    except anthropic.AuthenticationError:
        raise RuntimeError("API key inválida") from None
    except anthropic.RateLimitError:
        raise RuntimeError("rate limit de la API, reintenta") from None
    except anthropic.APIStatusError as e:
        raise RuntimeError(f"API {e.status_code}: {e.message}") from None
    except anthropic.APIConnectionError:
        raise RuntimeError("sin conexión con la API") from None
    except TypeError as e:  # así avisa el SDK que no encontró credenciales
        if "authentication" not in str(e):
            raise
        raise RuntimeError("falta ANTHROPIC_API_KEY") from None

    if response.stop_reason == "refusal":
        raise RuntimeError("el modelo rechazó la solicitud")
    return "".join(block.text for block in response.content if block.type == "text")


def ollama(png: bytes, model: str) -> str:
    """Modelo local vía Ollama (http://127.0.0.1:11434)."""
    body = {
        "model": model,
        "stream": False,
        "keep_alive": "30m",  # mantiene el modelo en memoria: ~0.6 s en caliente vs ~6 s en frío
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": PROMPT},
            {"role": "user", "content": USER_TEXT, "images": [base64.standard_b64encode(png).decode()]},
        ],
    }
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.load(response)["message"]["content"]
    except urllib.error.HTTPError as e:
        detail = json.loads(e.read() or b"{}").get("error", e.reason)
        raise RuntimeError(f"Ollama: {detail}") from None
    except urllib.error.URLError:
        raise RuntimeError("Ollama no responde en :11434 (¿brew services start ollama?)") from None


class Backend(NamedTuple):
    solve: Callable[[bytes, str], str]
    default_model: str


BACKENDS = {
    "claude-code": Backend(claude_code, "sonnet"),
    "api": Backend(api, "claude-opus-5-5"),
    "ollama": Backend(ollama, "qwen2.5vl:7b"),
}
