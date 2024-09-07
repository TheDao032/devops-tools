FROM python:3.12-slim

WORKDIR /app

COPY . .

RUN apt-get update && apt-get install -y curl gcc && apt-get clean
RUN pip install --no-cache-dir --upgrade -r requirements.txt

CMD ["./scripts/run.sh"]
