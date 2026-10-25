#!/usr/bin/env bash
# Script robusto para build de APK Flutter em CI (Codemagic, GHA, etc.)
set -euo pipefail

echo "=== Ambiente ==="
echo "PWD: $(pwd)"
echo "USER: $(whoami)"
command -v flutter >/dev/null
flutter --version

echo "=== Dependências ==="
flutter pub get

echo "=== Build release ==="
# Ajuste flavors aqui se o projeto tiver, ex:
# flutter build apk --release --flavor prod -t lib/main_prod.dart
flutter build apk --release --no-tree-shake-icons

echo "=== Localizando APKs gerados ==="
# Caminho canônico do Flutter
CANONICAL="build/app/outputs/flutter-apk"
mkdir -p "$CANONICAL"

mapfile -t APKS < <(find . -type f -name "*.apk" \
  ! -path "*/.dart_tool/*" \
  ! -path "*/intermediates/*" \
  ! -name "*debug*" \
  ! -name "*profile*" \
  | sort)

if [ "${#APKS[@]}" -eq 0 ]; then
  echo "ERRO: nenhum APK de release encontrado."
  echo "--- Estrutura de build/ ---"
  find build -type d 2>/dev/null | head -80 || true
  echo "--- Qualquer .apk no clone ---"
  find . -name "*.apk" 2>/dev/null || true
  exit 1
fi

echo "APKs encontrados:"
printf '  %s\n' "${APKS[@]}"

# Preferir app-release.apk; senão o primeiro release
TARGET=""
for apk in "${APKS[@]}"; do
  if [[ "$(basename "$apk")" == "app-release.apk" ]]; then
    TARGET="$apk"
    break
  fi
done
TARGET="${TARGET:-${APKS[0]}}"

DEST="$CANONICAL/app-release.apk"
if [ "$(realpath "$TARGET")" != "$(realpath "$DEST" 2>/dev/null || echo "")" ]; then
  cp -f "$TARGET" "$DEST"
fi

echo "=== Artefato final ==="
ls -lh "$DEST"
echo "SHA256: $(sha256sum "$DEST" | awk '{print $1}')"
echo "OK: $DEST"
