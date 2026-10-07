# copyEzz (versión anterior: Python + Hammerspoon)

> Reemplazada por la app nativa `CopyEzz.app` (ver el README de la raíz). Se conserva aquí hasta completar la migración.

Botón lateral del mouse (o ⌃⌥⌘A) → captura de la pantalla donde está el mouse → modelo de visión → la respuesta aparece en el **título de la pestaña** `http://127.0.0.1:8765` (p. ej. `b) CHARTOROWID`). La página muestra además la justificación, el motor y la latencia.

## Uso

```sh
cd ~/dev/copyEzz/legacy
uv run copyezz.py                      # motor claude-code (sonnet), abre la pestaña
uv run copyezz.py --model haiku        # más rápido
uv run copyezz.py --backend api        # API directa (requiere ANTHROPIC_API_KEY)
uv run copyezz.py --backend ollama     # local, qwen2.5vl:7b
```

El motor y el modelo también se cambian en vivo desde la página. Mientras piensa, el título es `…`; si falla, `⚠ <error>`. No fijes la pestaña: las pestañas fijadas solo muestran el ícono, no el título.

## Disparo (Hammerspoon)

`~/.hammerspoon/init.lua` carga `legacy/hammerspoon/copyezz.lua`:

- **Botón lateral "adelante"** del Keychron M3 mini (`MOUSE_BUTTON = 4`; usa `3` para el de "atrás"). El clic se consume para que el navegador no navegue.
- **⌃⌥⌘A** como alternativa de teclado.

Hammerspoon necesita permisos de **Accesibilidad** (atajo y mouse) y **Grabación de pantalla** (captura) en Ajustes del Sistema → Privacidad y seguridad. Tras editar el `.lua`: menú de Hammerspoon → *Reload Config*.

## Motores

| `--backend` | Modelo por defecto | Requiere |
|---|---|---|
| `claude-code` | `sonnet` | `claude` con sesión iniciada (tu suscripción) |
| `api` | `claude-opus-5-5` | `ANTHROPIC_API_KEY` |
| `ollama` | `qwen2.5vl:7b` | `brew services start ollama` + `ollama pull qwen2.5vl:7b` |

## Probar sin mouse

```sh
curl --data-binary @../samples/quiz-sample.png -H 'Content-Type: image/png' http://127.0.0.1:8765/solve
curl -X POST http://127.0.0.1:8765/solve   # sin body: el server captura con screencapture (necesita permiso para la terminal)
```

Cada respuesta queda registrada en `history.jsonl`.
