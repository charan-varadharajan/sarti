FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

RUN addgroup --system sarti && adduser --system --ingroup sarti sarti

COPY requirements-runtime.lock ./
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements-runtime.lock

COPY alembic.ini ./
COPY alembic ./alembic
COPY src ./src
COPY docker-entrypoint.sh ./

RUN chmod 0555 docker-entrypoint.sh && chown -R sarti:sarti /app

USER sarti
EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/v1/health/ready', timeout=2)"]

ENTRYPOINT ["./docker-entrypoint.sh"]
