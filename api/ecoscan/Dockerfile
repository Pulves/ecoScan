FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY ecoscan/requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch torchvision \
    && pip install --no-cache-dir --upgrade -r /app/requirements.txt

COPY ecoscan /app/ecoscan

CMD ["uvicorn", "ecoscan.app:app", "--host", "0.0.0.0", "--port", "8000"]
