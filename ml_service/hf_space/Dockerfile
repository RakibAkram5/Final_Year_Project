# Hugging Face Space (Docker SDK, free CPU basic) for the TaleemPlus ML API.
# Spaces route traffic to port 7860 and run the container as UID 1000.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/home/user \
    ML_ARTIFACT_DIR=/home/user/artifacts

RUN useradd -m -u 1000 user
WORKDIR /home/user/app

COPY --chown=user requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=user app ./app
USER user

EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7860/health', timeout=3)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
