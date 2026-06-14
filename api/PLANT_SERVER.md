# Servidor de reconhecimento de plantas

Este servidor FastAPI recebe uma imagem enviada pelo EcoScan e usa o
classificador YOLO11 salvo em `best.pt`. A imagem e processada em memoria e
nao e armazenada no computador.

## Preparacao

Use Python 3.11 ou 3.12. No PowerShell, a partir da raiz do projeto:

```powershell
cd api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r .\ecoscan\requirements.txt
```

Copie o modelo treinado para:

```text
api/ecoscan/best.pt
```

Opcionalmente, copie `model_metadata.json` para a mesma pasta. Esse arquivo
permite que a API devolva os nomes amigaveis em portugues e os dados exatos do
treinamento.

## Executar

Dentro da pasta `api`:

```powershell
python -m ecoscan.plant_server
```

O servidor escuta em todas as interfaces na porta `8000`:

- Documentacao interativa: `http://localhost:8000/docs`
- Saude do modelo: `GET http://localhost:8000/plants/health`
- Reconhecimento: `POST http://localhost:8000/plants/identify`

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
    "class_id": 1,
    "slug": "mango",
    "name": "Manga",
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

No emulador Android, use `http://10.0.2.2:8000`. Em um celular fisico, use o
IP local do computador, por exemplo `http://192.168.0.10:8000`; ambos devem
estar na mesma rede e a porta `8000` precisa estar liberada no firewall.

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
