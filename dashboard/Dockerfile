FROM python:3.11-slim

WORKDIR /app

# Install docker-compose
RUN apt-get update && \
    apt-get install -y docker-compose && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY app.py .
COPY static/ ./static/

# Expose port
EXPOSE 5000

CMD ["python", "app.py"]

