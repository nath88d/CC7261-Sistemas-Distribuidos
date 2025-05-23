FROM python:3.11

WORKDIR /app

COPY . .

RUN pip install --no-cache-dir -r requirements.txt
RUN pip install requests

# Executa bind_queues.py em segundo plano e inicia a API(main.py)
CMD ["sh", "-c", " uvicorn main:app --host 0.0.0.0 --port 8000"]
