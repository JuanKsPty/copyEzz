# CopyEzz

App de barra de menú para macOS. Presionas el botón lateral del mouse (o ⌃⌥⌘A), captura la pantalla donde está el mouse, un modelo de visión resuelve la pregunta de quiz visible y la respuesta aparece en el **título de la pestaña** `http://127.0.0.1:8765`, por ejemplo `b) TO_DATE`. La página muestra además la justificación, el motor usado y la latencia.

## Instalar

1. Descarga `CopyEzz-X.Y.Z.dmg` de [Releases](https://github.com/JuanKsPty/copyEzz/releases/latest) y arrastra **CopyEzz** a **Aplicaciones**.
2. La app no está notarizada por Apple, así que macOS la bloquea la primera vez. Ábrela una vez y luego ve a **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**. Alternativa en la terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/CopyEzz.app
   ```
3. Concede los permisos que pide (también aparecen como ⚠︎ en su menú):
   - **Accesibilidad**: para el botón del mouse y el atajo.
   - **Grabación de pantalla**: para la captura.
4. En **Ajustes… → Abrir CopyEzz al iniciar sesión** para que arranque sola.

Las versiones nuevas se instalan solas con Sparkle (o desde el menú: **Buscar actualizaciones…**), y los permisos se conservan.

## Uso

- **Botón lateral "adelante"** del mouse (botón 4) o **⌃⌥⌘A**. Ambos se cambian en Ajustes con **Cambiar** y presionando el botón o atajo nuevo. El clic se consume, así que el navegador no navega.
- La página `http://127.0.0.1:8765` se abre al iniciar (desactivable). Mientras piensa el título es `…`; si algo falla, `⚠ <error>`. No fijes la pestaña: las pestañas fijadas no muestran el título.
- Opcional: **Mostrar la respuesta también en la barra de menú**.
- **Contexto**: sube un `.txt` con apuntes, el temario o un banco de preguntas con **+ contexto .txt** en la página (o en **Ajustes → Contexto**). Se envía con cada captura y el modelo responde con ese material; si la pregunta no aparece ahí, usa lo que sabe. Uno a la vez (subir otro lo reemplaza), máximo 1 MB, en UTF-8, UTF-16 o Windows-1252. Se conserva al reiniciar y se quita con **×**. Con la API y con Claude Code el material queda en la caché de prompts, así que las capturas siguientes no lo vuelven a procesar.
- El motor y el modelo se cambian desde el menú, la página o Ajustes. Cada respuesta queda en `~/Library/Application Support/CopyEzz/history.jsonl`.

## Motores

| Motor | Modelo por defecto | Requiere |
|---|---|---|
| Claude Code | `sonnet` (`haiku` es más rápido) | `claude` instalado y con sesión iniciada; usa tu suscripción |
| API de Anthropic | `claude-opus-5-5` | API key (se guarda en el Llavero) |
| Ollama | `qwen2.5vl:7b` | `brew install ollama && brew services start ollama && ollama pull qwen2.5vl:7b` |

## Desarrollo

Requisitos: macOS 14+, Command Line Tools (`xcode-select --install`; Xcode no hace falta) y Google Chrome solo para regenerar el ícono o la muestra.

```sh
scripts/create-signing-cert.sh   # una vez: certificado propio para firmar (sin diálogos del Llavero)
make test                        # tests de CopyEzzCore (Swift Testing)
make run                         # arma dist/CopyEzz.app en debug, reemplaza la que corre y la abre

# Probar sin mouse: envía la muestra y mira el título de la pestaña en Chrome headless
curl --data-binary @samples/quiz-sample.png -H 'Content-Type: image/png' http://127.0.0.1:8765/solve
node scripts/title-check.mjs

# Cargar o quitar el contexto
curl --data-binary @apuntes.txt -H 'X-Filename: apuntes.txt' http://127.0.0.1:8765/context
curl -X DELETE http://127.0.0.1:8765/context
```

Estructura:

- `Sources/CopyEzzCore/`: lógica sin interfaz (HTTP, eventos SSE, motores, imágenes, historial), con tests en `Tests/`.
- `Sources/CopyEzz/`: la app (SwiftUI `MenuBarExtra`, server local con Network.framework, captura con ScreenCaptureKit, disparo con `CGEventTap`, Sparkle).
- `Resources/`: `index.html` (la página), plantilla de `Info.plist`, ícono.
- `scripts/`: empaquetado, firma, publicación y utilidades.

## Publicar una versión

1. Agrega la sección `## X.Y.Z` a `CHANGELOG.md` y haz commit.
2. `make release VERSION=X.Y.Z`: corre los tests, arma la app universal firmada, crea el `.dmg`, lo firma para Sparkle, genera `appcast.xml`, crea el tag y la GitHub Release.

La firma usa el certificado y la llave de Sparkle de `~/CopyEzz-signing/` (fuera del repo). **Respalda esa carpeta**: sin ella, las versiones nuevas no podrán actualizar a las ya instaladas.

## Versión anterior

`legacy/` contiene la primera versión (server Python + Hammerspoon), reemplazada por esta app.
