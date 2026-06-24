# Servidor de reconhecimento de plantas

Este servidor FastAPI recebe uma imagem enviada pelo EcoScan e usa o
classificador YOLO11 salvo em `best.pt`. O reconhecimento e processado em
memoria; quando o usuario salva o resultado, imagem e metadados sao persistidos
no PostgreSQL.

## Preparacao

Use Python 3.11 ou 3.12. No PowerShell, a partir da raiz do projeto:

```powershell
cd api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r .\ecoscan\requirements.txt
```

Para executar diretamente com Python, copie o modelo treinado para:

```text
api/ecoscan/best.pt
```

Como alternativa, defina `ECOSCAN_MODEL_PATH` com o caminho absoluto do peso.
O arquivo `model_metadata.json` versionado no projeto permite que a API devolva
os nomes amigaveis em portugues e os dados do treinamento.

## Executar

Dentro da pasta `api`:

```powershell
python -m ecoscan.plant_server
```

O comando inicia a API unificada de usuarios, autenticacao e reconhecimento.
O servidor escuta em todas as interfaces na porta `8000`:

- Documentacao interativa: `http://localhost:8000/docs`
- Cadastro de usuario: `POST http://localhost:8000/users/`
- Autenticacao: `POST http://localhost:8000/auth/token`
- Renovacao da sessao: `POST http://localhost:8000/auth/refresh`
- Saude do modelo: `GET http://localhost:8000/plants/health`
- Reconhecimento: `POST http://localhost:8000/plants/identify`
- Salvar/listar historico: `POST/GET http://localhost:8000/history`
- Remover do historico: `DELETE http://localhost:8000/history/{id}`
- Listar biblioteca: `GET http://localhost:8000/library`
- Adicionar/remover da biblioteca: `PUT/DELETE http://localhost:8000/library/{id}`

Sem o arquivo `best.pt`, os recursos de usuario e autenticacao continuam
funcionando e o reconhecimento responde com HTTP `503`.

A autenticacao retorna um access token de curta duracao e um refresh token.
O aplicativo armazena ambos com `flutter_secure_storage` e usa
`/auth/refresh` para renovar a sessao sem exigir um novo login.

## Docker

Crie `api/.env` a partir de `api/.env.example` e informe o caminho absoluto do
modelo no computador:

```text
ECOSCAN_MODEL_HOST_PATH=C:/caminho/para/best.pt
```

O Compose monta o peso no container em modo somente leitura. Em seguida,
execute:

```powershell
cd api
docker compose up -d --build
docker compose ps
```

O Postgres fica disponivel na porta `5432` e a API na porta `8000`.
O container da API so fica saudavel quando o modelo estiver carregado.

Teste pelo PowerShell:

```powershell
curl.exe -X POST "http://localhost:8000/plants/identify" `
  -F "image=@C:\caminho\foto-planta.jpg"
```

O limiar e a quantidade de alternativas podem ser informados na URL:

```text
POST /plants/identify?confidence_threshold=0.60&top_k=3
```

Exemplo de resposta:

```json
{
  "success": true,
  "recognized": true,
  "plant": {
    "class_id": 3,
    "slug": "mango",
    "name": "Mangueira",
    "confidence": 0.932114
  },
  "alternatives": [],
  "threshold": 0.6,
  "model": {
    "task": "classification",
    "architecture": "yolo11s-cls.pt",
    "image_size": 224
  }
}
```

## Historico e biblioteca

Os endpoints de persistencia exigem `Authorization: Bearer <token>`. Para
salvar uma identificacao, envie `multipart/form-data` para `/history` com:

- `image`: arquivo da foto;
- `plant_name`: nome exibido;
- `plant_slug`: classe do modelo;
- `confidence`: confianca entre `0` e `1`;
- `recognized`: `true` ou `false`;
- `add_to_library`: adiciona tambem a biblioteca quando `true`.

As listagens retornam apenas registros pertencentes ao usuario autenticado.
A imagem protegida pode ser recuperada pela URL informada em `image_url`.

## Chamada no Flutter

Adicione o pacote `http` ao Flutter e envie a foto como multipart com o campo
chamado `image`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> identifyPlant(
  String imagePath,
  String serverAddress,
) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$serverAddress/plants/identify'),
  );
  request.files.add(
    await http.MultipartFile.fromPath('image', imagePath),
  );

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode != 200) {
    throw Exception('Falha na identificacao: ${response.body}');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}
```

No emulador Android, use `http://10.0.2.2:8000`. Em um celular fisico conectado
por USB, execute `adb reverse tcp:8000 tcp:8000` e use
`http://127.0.0.1:8000`. Tambem e possivel usar o IP local do computador quando
ambos estiverem na mesma rede e a porta `8000` estiver liberada no firewall.

## Configuracao opcional

As seguintes variaveis de ambiente podem ser definidas antes de iniciar:

```powershell
$env:ECOSCAN_MODEL_PATH = "C:\modelos\best.pt"
$env:ECOSCAN_METADATA_PATH = "C:\modelos\model_metadata.json"
$env:ECOSCAN_DEVICE = "cpu"
$env:ECOSCAN_HOST = "0.0.0.0"
$env:ECOSCAN_PORT = "8000"
python -m ecoscan.plant_server
```

Para usar uma GPU NVIDIA configurada para o PyTorch, defina
`ECOSCAN_DEVICE=0`.
