FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8002

WORKDIR /srv/maybeflat/backend_api

COPY backend_api/requirements.txt ./requirements.txt

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY backend_api/app ./app
COPY backend_api/generate_tiles.py ./generate_tiles.py
COPY docs/data ../docs/data

EXPOSE 8002

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8002} --workers ${MAYBEFLAT_API_WORKERS:-4}"]
