FROM python:3.12-alpine

RUN pip install --no-cache-dir gallery-dl requests && \
    apk add --no-cache ffmpeg

# Keep container alive so we can docker exec into it
CMD ["tail", "-f", "/dev/null"]
