# Publicacao da API no Render

O Render fornece a URL HTTPS publica usada pelo aplicativo e elimina a
dependencia de o celular estar na mesma rede do computador. O arquivo
`render.yaml`, na raiz do repositorio, cria:

- um Web Service Docker para a API FastAPI;
- um PostgreSQL gerenciado;
- uma chave JWT aleatoria;
- a conexao privada entre API e banco.

## 1. Publicar o modelo

O `best.pt` nao deve ser adicionado ao historico Git. Publique-o como um asset
de GitHub Release no repositorio `Pulves/ecoScan`:

1. Abra **Releases > Draft a new release** no GitHub.
2. Crie a tag `model-v1`.
3. Anexe o arquivo `best.pt` usado localmente.
4. Publique a release.
5. Copie a URL HTTPS do asset. Para uma release publica, ela tera formato
   semelhante a:

```text
https://github.com/Pulves/ecoScan/releases/download/model-v1/best.pt
```

O Blueprint ja contem o SHA-256 do modelo local atual:

```text
d03b0dc16937052131ebb1c391d70aa873e42c11d383bb2d9e6a0bdbe61be847
```

Ao substituir o modelo, calcule o novo valor e atualize
`ECOSCAN_MODEL_SHA256` em `render.yaml`:

```powershell
Get-FileHash -Algorithm SHA256 C:\caminho\para\best.pt
```

Tambem e possivel usar armazenamento de objetos. Nesse caso, use uma URL HTTPS
estavel; uma URL assinada que expire pode impedir reinicializacoes futuras.

## 2. Criar os servicos

1. Envie as alteracoes para a branch que sera publicada, por exemplo
   `front_app`.
2. Entre em <https://dashboard.render.com> e conecte a conta do GitHub.
3. Selecione **New > Blueprint**.
4. Escolha `Pulves/ecoScan` e a branch `front_app`.
5. Confirme o arquivo `render.yaml`.
6. Quando solicitado, informe `ECOSCAN_MODEL_URL` com a URL do passo anterior.
7. Aplique o Blueprint e acompanhe os logs ate o deploy ficar **Live**.

O container baixa o modelo, valida seu SHA-256, aplica as migracoes Alembic e
inicia o Uvicorn na porta fornecida pelo Render. A plataforma fornece TLS e uma
URL semelhante a `https://ecoscan-api.onrender.com`.

Valide a API no PowerShell:

```powershell
Invoke-RestMethod https://ecoscan-api.onrender.com/plants/health
```

O resultado deve conter `status=ready` e `model_loaded=true`.

## 3. Configurar recuperacao de senha

No Web Service, abra **Environment** e adicione as credenciais do provedor:

```text
SMTP_HOST=smtp.example.com
SMTP_PORT=2525
SMTP_USERNAME=usuario
SMTP_PASSWORD=senha
SMTP_FROM_EMAIL=noreply@example.com
SMTP_FROM_NAME=EcoScan
SMTP_USE_TLS=true
SMTP_USE_SSL=false
```

O plano gratuito do Render bloqueia saidas SMTP nas portas 25, 465 e 587.
Use uma porta alternativa autorizada pelo provedor, como 2525, ou adapte o
envio para a API HTTPS do servico de email. Mantenha
`PASSWORD_RESET_EXPOSE_TOKEN=false`.

## 4. Apontar o Flutter para o Render

Para executar no Redmi usando a API online:

```powershell
flutter run -d bca75a35 `
  --dart-define=ECOSCAN_API_BASE_URL=https://ecoscan-api.onrender.com
```

Para gerar o APK release:

```powershell
flutter clean
flutter pub get
flutter build apk --release `
  --dart-define=ECOSCAN_API_BASE_URL=https://ecoscan-api.onrender.com
```

Para publicacao na Play Store, troque `apk` por `appbundle`. Nao inclua barra
no final da URL. O app release recusa uma API sem HTTPS.

## 5. Limites do plano gratuito

O plano gratuito e apropriado para homologacao, mas nao para producao:

- o Web Service adormece depois de 15 minutos sem trafego e o primeiro acesso
  pode levar cerca de um minuto;
- os 512 MB de RAM podem ser insuficientes para PyTorch e Ultralytics; se houver
  erro de memoria, use no minimo o plano Standard de 2 GB;
- o PostgreSQL gratuito expira depois de 30 dias, tem 1 GB e nao possui backup;
- imagens e identificacoes ficam no PostgreSQL, nao no sistema de arquivos
  efemero do container.

Para uso real, escolha PostgreSQL pago com backup e uma instancia da API com
memoria suficiente para o modelo.

Referencias oficiais:

- <https://render.com/docs/infrastructure-as-code>
- <https://render.com/docs/web-services>
- <https://render.com/docs/free>
- <https://render.com/docs/postgresql-creating-connecting>
