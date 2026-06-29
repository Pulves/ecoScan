# Publicacao do EcoScan

## 1. Chave de assinatura Android

Gere a chave de upload uma unica vez:

```powershell
.\android\generate-release-keystore.ps1
```

O comando cria:

- `android/app/upload-keystore.jks`;
- `android/key.properties`.

Os dois arquivos sao ignorados pelo Git. Guarde copias em um cofre de segredos
e em backup seguro. Perder a chave pode impedir futuras atualizacoes do app.

## 2. Segredos da API

Copie `api/.env.production.example` para `api/.env.production` e substitua
todos os valores de exemplo. Use valores aleatorios independentes para
`POSTGRES_PASSWORD` e `SECRET_KEY`.

Nunca envie `.env.production`, chaves, senhas SMTP ou keystores ao Git.

## 3. HTTPS

Para hospedar a API no Render, use o [guia especifico](RENDER.md). O Render
fornece o endpoint HTTPS e o PostgreSQL gerenciado descritos naquele fluxo.

Para publicacao em servidor proprio, siga os passos abaixo.

Crie os registros DNS A/AAAA de `ECOSCAN_DOMAIN` apontando para o servidor.
Libere as portas 80 e 443. O Caddy obtem e renova automaticamente o certificado
TLS e encaminha as requisicoes para a API.

Inicie a producao:

```powershell
cd api
docker compose `
  --env-file .env.production `
  -f docker-compose.yml `
  -f docker-compose.prod.yml `
  up -d --build
```

A API recusa a inicializacao em producao quando:

- a URL publica nao usa HTTPS;
- a chave JWT e curta ou ainda e a chave de desenvolvimento;
- a senha padrao do PostgreSQL continua na URL;
- o token de recuperacao esta exposto;
- CORS ou hosts usam curingas.

## 4. CORS

Defina `CORS_ALLOWED_ORIGINS` com as origens HTTPS autorizadas, separadas por
virgula. Aplicativos Android nativos nao dependem de CORS; inclua somente
frontends web realmente existentes.

Exemplo:

```text
CORS_ALLOWED_ORIGINS=https://www.example.com,https://admin.example.com
```

## 5. App Bundle

Gere o AAB apontando exclusivamente para a API HTTPS:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release `
  --dart-define=ECOSCAN_API_BASE_URL=https://api.example.com
```

Artefato:

```text
build/app/outputs/bundle/release/app-release.aab
```

O release falha quando a chave de assinatura esta ausente. O aplicativo tambem
recusa URL HTTP em modo release.

## 6. Politica de privacidade

Publique `PRIVACY_POLICY.md` em uma URL HTTPS acessivel sem login e informe essa
URL na Google Play Console. Atualize a politica sempre que os dados coletados,
os fornecedores ou os prazos de retencao mudarem.

Informe tambem a URL publica de `ACCOUNT_DELETION.md` no campo de exclusao de
conta da Play Console. A politica e a exclusao de conta tambem estao acessiveis
dentro do aplicativo em **Configuracoes**.
