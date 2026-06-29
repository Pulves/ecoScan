# EcoScan

EcoScan e um aplicativo Flutter para Android que identifica plantas a partir
da camera, salva historico e biblioteca e se comunica com uma API FastAPI.

Documentos de publicacao:

- [Guia de release](docs/RELEASE.md)
- [Hospedagem da API no Render](docs/RENDER.md)
- [Politica de privacidade](PRIVACY_POLICY.md)

## Telas implementadas

- **Login**: tela inicial com logo, campos de login e senha, botao de entrada e link de recuperacao de senha.
- **Historico**: lista de plantas ja identificadas, agrupadas por data, com cards contendo imagem ilustrativa, nome e data.
- **Minha Biblioteca**: lista de plantas adicionadas pelo usuario, com acao visual de remocao.
- **Captura**: tela de captura com pre-visualizacao ilustrativa, botao de camera e resultado simulado de identificacao.

## Alteracoes realizadas

- Substituicao do template inicial do contador por uma experiencia completa do EcoScan.
- Criacao de componentes reutilizaveis para logo, campos de texto, cards de plantas, cabecalho e barra de navegacao.
- Implementacao de navegacao inferior entre Biblioteca, Historico e Captura.
- Inclusao de um fluxo simulado de deteccao: ao tocar no botao de camera, o app mostra um resultado e permite adicionar a planta ao historico e a biblioteca.
- Atualizacao do nome Android do aplicativo para `EcoScan`.
- Declaracao da permissao de camera no AndroidManifest para preparar a integracao futura com a camera real.
- Atualizacao do teste de widget para validar o fluxo principal entre as telas.

## Estrutura principal

```text
lib/
  main.dart                  # Telas, componentes e navegacao do app

test/
  widget_test.dart            # Teste basico do fluxo de telas

android/app/src/main/
  AndroidManifest.xml         # Nome do app e permissao de camera
```

## Requisitos

- Flutter SDK instalado e configurado no PATH.
- Android Studio instalado.
- Um emulador Android ou smartphone Android com depuracao USB ativada.

Verifique o ambiente com:

```bash
flutter doctor
```

## Como executar

Na raiz do projeto:

```bash
flutter pub get
flutter run
```

Para rodar em um celular especifico:

```bash
flutter devices
flutter run -d ID_DO_DISPOSITIVO
```

Depois da primeira instalacao, o app debug funciona sem cabo USB quando o
celular e o computador estao na mesma rede Wi-Fi. A API e descoberta
automaticamente na porta 8000. Consulte
[a configuracao de rede local](api/PLANT_SERVER.md#uso-sem-cabo-usb-na-rede-local).

Para usar o aplicativo fora da rede local, publique a API no Render e gere o
app com a URL HTTPS em `ECOSCAN_API_BASE_URL`. Consulte o
[guia de hospedagem no Render](docs/RENDER.md).

## Como testar no smartphone Android

1. Ative as opcoes de desenvolvedor no Android.
2. Ative a opcao **Depuracao USB**.
3. Conecte o smartphone ao computador via USB.
4. Aceite a autorizacao de depuracao exibida no celular.
5. Execute `flutter devices` para confirmar se o aparelho foi reconhecido.
6. Execute `flutter run` para instalar e abrir o app.

Tambem e possivel abrir o projeto no Android Studio, selecionar o dispositivo conectado e clicar em **Run**.

## Comandos de validacao

Antes de publicar no GitHub, rode:

```bash
dart format lib/main.dart test/widget_test.dart
flutter analyze
flutter test
```

## Como subir para o GitHub

Caso o projeto ainda nao esteja versionado:

```bash
git init
git add .
git commit -m "Implementa telas iniciais do EcoScan"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/ecoscan_app.git
git push -u origin main
```

Se o repositorio ja existir localmente:

```bash
git status
git add README.md lib/main.dart test/widget_test.dart android/app/src/main/AndroidManifest.xml
git commit -m "Documenta e implementa telas iniciais do EcoScan"
git push
```

## Proximos passos

- Integrar camera real usando um pacote como `camera`.
- Implementar permissao de camera em tempo de execucao.
- Conectar um modelo de reconhecimento de plantas, por exemplo TensorFlow Lite.
- Persistir historico e biblioteca em armazenamento local ou banco de dados.
- Criar autenticacao real para login.
- Adicionar imagens reais ou assets proprios para as plantas.
