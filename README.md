# SincroLocal

Prévia das telas: abertura, cópia para o cartão SD deste aparelho e sincronização com o aparelho B.

Isto ainda não é o APK Android. É o protótipo web das telas. O Codemagic só gera o APK quando o repositório for um projeto Flutter.

## No telemóvel (Termux)

```sh
pkg install git unzip
cd $HOME
unzip $HOME/storage/downloads/sincro-local.zip -d $HOME/sincro-local
cd $HOME/sincro-local
git init
git add .
git commit -m "Prévia das telas do SincroLocal"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/sincro-local.git
git push -u origin main
```

Crie o repositório vazio e privado no GitHub antes do `remote`. No push, o GitHub pede um token (Settings → Developer settings → Personal access tokens), não a senha da conta.
