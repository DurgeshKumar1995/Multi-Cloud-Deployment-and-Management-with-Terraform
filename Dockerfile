FROM python:3.13-alpine

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PORT=8080 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app/server.py /app/server.py

RUN addgroup -S app && adduser -S -G app -u 10001 app \
    && chown -R app:app /app

USER app
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O - http://127.0.0.1:8080/health >/dev/null || exit 1

CMD ["python", "/app/server.py"]

