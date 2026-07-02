# EcoScan

EcoScan e um aplicativo Flutter para Android que identifica plantas pela camera
do dispositivo. O app utiliza uma API FastAPI, PostgreSQL e um modelo YOLO11 de
classificacao, alem de manter historico e jardim por usuario.

## Funcionalidades

- cadastro, login, renovacao de sessao e recuperacao de senha;
- captura de imagens com a camera do dispositivo;
- classificacao de plantas com o modelo `best.pt`;
- historico de identificacoes e imagens;
- jardim pessoal com inclusao e remocao de plantas;
- detalhes botanicos e cuidados para as classes reconhecidas;
- edicao de perfil e exclusao de conta.

## Branch do projeto

O estado atual do aplicativo esta na branch `front_app`. Ela nao e a branch
padrao do repositorio. Depois de clonar, selecione-a explicitamente:

```powershell
git clone https://github.com/Pulves/ecoScan.git
cd ecoScan
git checkout front_app
```

## Requisitos

- Git;
- Flutter SDK compativel com Dart `^3.12.0`;
- Android Studio e Android SDK, incluindo `adb`;
- Docker Desktop com Docker Compose;
- Node.js disponivel no `PATH`;
- PowerShell;
- smartphone Android com depuracao USB ativada.

Confirme o ambiente Flutter com:

```powershell
flutter doctor
```

## Configuracao local

Crie o arquivo local de configuracao da API:

```powershell
Copy-Item api\.env.example api\.env
```

Edite `api/.env` e substitua, no minimo, `POSTGRES_PASSWORD` e `SECRET_KEY` por
valores locais longos e aleatorios. O modelo treinado ja esta versionado em
`api/ecoscan/best.pt`, e o exemplo aponta para ele com:

```text
ECOSCAN_MODEL_HOST_PATH=./ecoscan/best.pt
```

Em desenvolvimento, `PASSWORD_RESET_EXPOSE_TOKEN=true` devolve o codigo de
recuperacao no proprio app. Para envio por email, defina essa opcao como `false`
e configure as variaveis SMTP.

## Iniciar API e banco

Na raiz do projeto:

```powershell
Set-Location api
docker compose up -d --build
Set-Location ..
```

O PostgreSQL fica restrito a `127.0.0.1:5432`, e a API Docker responde em
`127.0.0.1:18000`. Verifique o estado dos containers com:

```powershell
Set-Location api
docker compose ps
Set-Location ..
```

## Executar no Android por USB

Conecte o celular, autorize a depuracao USB e confirme que ele aparece em:

```powershell
adb devices
```

Prepare as dependencias Flutter, inicie o relay local e execute o aplicativo:

```powershell
flutter pub get
.\scripts\start-local-usb.ps1
flutter run -d ID_DO_DISPOSITIVO
```

O script encaminha `127.0.0.1:8000` para a API Docker em
`127.0.0.1:18000` e cria a regra `adb reverse`. O cabo USB deve permanecer
conectado durante o uso.

Caso mais de um dispositivo esteja conectado, informe o identificador:

```powershell
.\scripts\start-local-usb.ps1 -DeviceId ID_DO_DISPOSITIVO
```

Para remover o redirecionamento e encerrar o relay:

```powershell
.\scripts\stop-local-usb.ps1
```

Para encerrar a API e o banco:

```powershell
Set-Location api
docker compose down
Set-Location ..
```

## Validacao

Execute as verificacoes Flutter:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Os testes da API exigem um ambiente Python com as dependencias de
`api/ecoscan/requirements.txt` e `pytest`:

```powershell
python -m pytest api\tests -q
```

## Estrutura principal

```text
lib/                         Aplicativo Flutter
api/ecoscan/                 API, modelo e migracoes
api/tests/                   Testes da API
scripts/                     Relay local e automacao ADB
machine_learning/            Treinamento e documentacao do modelo
test/                        Testes Flutter
```

O arquivo `api/.env`, bancos locais, builds, ambientes virtuais e demais
segredos nao devem ser enviados ao Git.
