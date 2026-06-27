FROM python:3.14-slim

# Define o diretório de trabalho dentro do container
WORKDIR /ecoscan

RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copia o arquivo de dependências primeiro (otimiza o cache de camadas do Docker)
COPY requirements.txt /ecoscan/requirements.txt

# Instala as dependências do Python
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir --upgrade -r /ecoscan/requirements.txt

# Copia o restante do código da aplicação para o container
COPY . /ecoscan

# Comando padrão para iniciar a aplicação caso o docker-compose não sobrescreva
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]