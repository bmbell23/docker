FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir git+https://github.com/ping/odmpy.git && \
    pip install --no-cache-dir playwright && \
    playwright install chromium --with-deps

COPY . .

ENV PYTHONUNBUFFERED=1
ENV LIBBY_SETTINGS=/settings
ENV WATCH_DIR=/books

EXPOSE 5007
CMD ["python", "app.py"]
