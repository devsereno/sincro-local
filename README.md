# Folha Certa

App Flutter de ponto eletrônico e jornada de trabalho.

## Rodar localmente

```bash
flutter pub get
flutter run
```

## APK release

```bash
flutter build apk --release --no-tree-shake-icons
```

Artefato:

`build/app/outputs/flutter-apk/app-release.apk`

## CI (Codemagic)

O arquivo `codemagic.yaml` na raiz dispara o workflow **Folha Certa Android APK** em `main` e `develop`.

A máquina (Mac mini M2) instala o Android SDK toda vez. Isso não recria o projeto. O passo de CI não chama `flutter create`. A pasta `android/` tem que estar commitada no git.
