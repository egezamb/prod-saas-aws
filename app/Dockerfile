# Small, non-root production image. The base is pinned by digest, so a rebuilt tag upstream cannot
# change what ships; Dependabot proposes the next digest.
FROM python:3.14-slim@sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Run as a non-root user with a fixed numeric ID, so a runtime that checks "non-root" can tell
# without reading /etc/passwd, and file ownership stays the same across rebuilds.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8000
# exec makes uvicorn PID 1, so the SIGTERM ECS sends on a deploy reaches it and it shuts down
# cleanly, instead of sh ignoring it until the task is killed after the 30 s stop timeout.
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
