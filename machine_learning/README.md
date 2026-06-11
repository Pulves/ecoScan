# Treinamento do classificador de plantas

O arquivo `kaggle_yolo11_plant_classification.ipynb` prepara e treina um
classificador YOLO11 com o dataset Kaggle **Plant Classification**.

## Modelo escolhido

Foi escolhido `yolo11s-cls.pt`. Para ate cinco classes e no maximo cerca de
500 imagens por classe, ele oferece um equilibrio melhor que:

- `yolo11n-cls`: mais rapido, mas com menor capacidade de extrair detalhes.
- `yolo11m/l/x-cls`: mais pesados e mais propensos a sobreajuste neste dataset.

Este e um modelo de classificacao, nao de deteccao. As pastas sao os rotulos e
nao existem anotacoes de bounding boxes. A foto enviada pela API deve conter
uma planta principal. Para localizar varias plantas na mesma foto seria
necessario criar anotacoes e treinar um modelo de deteccao.

## Como executar no Kaggle

1. Crie um notebook Kaggle e anexe o dataset **Plant Classification**.
2. Importe `kaggle_yolo11_plant_classification.ipynb`.
3. Em **Settings > Accelerator**, selecione uma GPU.
4. Habilite internet para instalar o pacote `ultralytics`.
5. Edite `SELECTED_PLANTS` na secao de configuracao, mantendo de 2 a 5 nomes.
6. Execute todas as celulas em ordem.
7. Baixe `/kaggle/working/best.pt` pela aba de outputs.

Se a busca automatica nao localizar as classes, defina `SOURCE_ROOT` com o
caminho exibido no painel de dados do Kaggle.

### Erro ao instalar o Ultralytics

Se a primeira celula terminar com `CalledProcessError` ou `RuntimeError`,
verifique **Notebook options/Settings > Internet** e deixe a opcao ligada.
O acesso tambem e usado para baixar `yolo11s-cls.pt` na primeira execucao.

A celula atual reutiliza o Ultralytics quando uma versao compativel ja esta
instalada e exibe a saida completa do `pip` quando houver falha. Em ambientes
sem acesso a internet, tambem e possivel anexar ao notebook um dataset contendo
um arquivo `ultralytics-*.whl`; a celula o localizara automaticamente.

## Saidas

- `best.pt`: modelo PyTorch que deve ser carregado pela API.
- `ecoscan_yolo11s_classifier.zip`: modelo, metadados, manifesto e graficos.
- `model_metadata.json`: IDs, nomes das classes e metricas de teste.
- `split_manifest.csv`: rastreabilidade das divisoes de treino, validacao e
  teste.

O notebook tambem inclui `prediction_to_api_json`, que demonstra o contrato de
resposta esperado pelo cliente Flutter.

## Observacao para producao

Como o modelo conhece somente as classes treinadas, ele sempre tentara escolher
uma delas. O limiar de confianca reduz respostas fracas, mas uma API de producao
deve considerar uma classe adicional `unknown` com outras plantas e fundos
comuns para rejeitar entradas fora do dominio.

Antes de distribuir a API, verifique o licenciamento do Ultralytics. Os modelos
YOLO11 sao disponibilizados sob AGPL-3.0 ou licenca Enterprise.
