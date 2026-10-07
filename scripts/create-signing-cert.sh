#!/bin/bash
# Prepara (una sola vez) la firma de CopyEzz: un certificado autofirmado "CopyEzz Self-Signed" dentro de
# un llavero dedicado (~/Library/Keychains/copyezz-signing.keychain-db) con contraseña aleatoria, para que
# codesign firme sin pedir tu contraseña.
#
# En $1 (por defecto ~/CopyEzz-signing) quedan el .p12 y las contraseñas: respáldalo en un lugar seguro.
# Si se pierde, las versiones nuevas no podrán actualizar a las ya instaladas. No lo subas al repo.
set -euo pipefail

NAME="CopyEzz Self-Signed"
BACKUP=${1:-$HOME/CopyEzz-signing}
KEYCHAIN="$HOME/Library/Keychains/copyezz-signing.keychain-db"
P12="$BACKUP/copyezz-signing.p12"

mkdir -p "$BACKUP"
chmod 700 "$BACKUP"

if [ ! -f "$P12" ]; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  # /usr/bin/openssl (LibreSSL) genera un .p12 que `security import` acepta sin opciones extra.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
  /usr/bin/openssl rand -base64 24 > "$BACKUP/p12-password.txt"
  /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$P12" -passout "file:$BACKUP/p12-password.txt"
  chmod 600 "$P12" "$BACKUP/p12-password.txt"
  echo "Certificado nuevo en $P12"
fi

if [ ! -f "$BACKUP/keychain-password.txt" ]; then
  /usr/bin/openssl rand -base64 24 > "$BACKUP/keychain-password.txt"
  chmod 600 "$BACKUP/keychain-password.txt"
fi
KEYCHAIN_PASSWORD=$(cat "$BACKUP/keychain-password.txt")

if [ ! -f "$KEYCHAIN" ]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"  # sin bloqueo automático
fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

if ! security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  security import "$P12" -k "$KEYCHAIN" -P "$(cat "$BACKUP/p12-password.txt")" -T /usr/bin/codesign >/dev/null
  # Permite que codesign use la llave sin mostrar diálogos.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
fi

echo "Listo: \"$NAME\" en $KEYCHAIN (respaldo en $BACKUP)"
