FROM python:3.12-slim

# Avoid prompts during install (e.g. tzdata) and keep image small
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install system dependencies required for building Python wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only requirements first to leverage Docker layer caching
COPY QuakeWatch/requirements.txt ./requirements.txt

RUN pip install -r requirements.txt

COPY . .

WORKDIR /app/QuakeWatch

# Add user to avoid running as root
RUN useradd -m appuser && chown -R appuser /app
USER appuser

EXPOSE 5000

CMD ["python", "app.py"]