#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYSTORE_PATH="${ROOT_DIR}/android/app/release/cineo-release.keystore"
PROPERTIES_PATH="${ROOT_DIR}/android/key.properties"
KEY_ALIAS="${ANDROID_KEY_ALIAS:-cineo}"

if [[ -f "${KEYSTORE_PATH}" && -f "${PROPERTIES_PATH}" && "${FORCE_SIGNING_SETUP:-0}" != "1" ]]; then
  echo "Android signing keystore already exists: ${KEYSTORE_PATH}"
  exit 0
fi

if [[ -f "${KEYSTORE_PATH}" && ! -f "${PROPERTIES_PATH}" && "${FORCE_SIGNING_SETUP:-0}" != "1" ]]; then
  echo "error: keystore exists but android/key.properties is missing; refusing to overwrite the key." >&2
  echo "Restore key.properties or set FORCE_SIGNING_SETUP=1 if you intentionally want a new key." >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "error: keytool is required. Install a JDK and try again." >&2
  exit 1
fi

mkdir -p "$(dirname "${KEYSTORE_PATH}")"

STORE_PASSWORD="${ANDROID_KEYSTORE_PASSWORD:-$(openssl rand -hex 24)}"
KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-${STORE_PASSWORD}}"

rm -f "${KEYSTORE_PATH}"
keytool -genkeypair \
  -v \
  -storetype JKS \
  -keystore "${KEYSTORE_PATH}" \
  -alias "${KEY_ALIAS}" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "${STORE_PASSWORD}" \
  -keypass "${KEY_PASSWORD}" \
  -dname "CN=Cineo, OU=Development, O=Cineo, L=Singapore, ST=Singapore, C=SG"

cat >"${PROPERTIES_PATH}" <<EOF
storePassword=${STORE_PASSWORD}
keyPassword=${KEY_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=app/release/cineo-release.keystore
EOF

chmod 600 "${PROPERTIES_PATH}" "${KEYSTORE_PATH}"
echo "Created local Android signing keystore: ${KEYSTORE_PATH}"
echo "The keystore and key.properties are ignored by Git. Keep them for future updates."
