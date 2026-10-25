#!/usr/bin/env bash
# Sobe a correção do APK para o GitHub sem apagar o resto do repositório.
# Uso, na pasta deste zip já descompactado:
#   bash subir_github.sh https://github.com/SEU_USUARIO/folha-certa.git
set -euo pipefail

REPO_URL="${1:-}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

if ! command -v git >/dev/null 2>&1; then
  echo "Git não está instalado."
  exit 1
fi

if [ -z "$REPO_URL" ]; then
  echo "Informe a URL do repositório que o Codemagic já usa."
  echo "Exemplo:"
  echo "  bash subir_github.sh https://github.com/SEU_USUARIO/folha-certa.git"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Clonando $REPO_URL"
git clone --depth 1 "$REPO_URL" "$WORK/repo"
cd "$WORK/repo"

copy() {
  local rel="$1"
  mkdir -p "$(dirname "$rel")"
  cp -a "$ROOT/$rel" "$rel"
}

copy android/settings.gradle
copy android/gradle.properties
copy android/app/build.gradle
copy android/gradle/wrapper/gradle-wrapper.properties
copy android/gradle/wrapper/gradle-wrapper.jar
copy android/gradlew
copy android/gradlew.bat
copy codemagic.yaml
copy README.md
chmod 755 android/gradlew

git add \
  android/settings.gradle \
  android/gradle.properties \
  android/app/build.gradle \
  android/gradle/wrapper/gradle-wrapper.properties \
  android/gradle/wrapper/gradle-wrapper.jar \
  android/gradlew \
  android/gradlew.bat \
  codemagic.yaml \
  README.md

if git diff --cached --quiet; then
  echo "Nada mudou. Esses arquivos já estão iguais no GitHub."
  exit 0
fi

git status --short
git commit -m "Corrige o APK: Gradle 8.14.3, AGP 8.11.1 e sem flutter create"
git push origin HEAD

echo
echo "Enviado. No Codemagic, rode de novo o workflow Folha Certa Android APK."
