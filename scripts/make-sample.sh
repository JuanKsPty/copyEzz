#!/bin/bash
# Renderiza samples/quiz-sample.html a samples/quiz-sample.png con Chrome headless.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$PWD/samples/quiz-sample.png"
PROFILE=$(mktemp -d)
rm -f "$OUT"

# Chrome headless reciente no siempre termina tras --screenshot: se cierra al aparecer el archivo.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$PROFILE" \
  --window-size=1440,520 --screenshot="$OUT" "file://$PWD/samples/quiz-sample.html" 2>/dev/null &
CHROME_PID=$!
trap 'kill "$CHROME_PID" 2>/dev/null || true; wait "$CHROME_PID" 2>/dev/null || true; rm -rf "$PROFILE" || true' EXIT

for _ in $(seq 1 50); do
  [ -s "$OUT" ] && break
  sleep 0.2
done
[ -s "$OUT" ] || { echo "Chrome no generó $OUT" >&2; exit 1; }
sleep 0.5  # deja terminar la escritura
echo "samples/quiz-sample.png"
