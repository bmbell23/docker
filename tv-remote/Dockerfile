FROM python:3.12-alpine
WORKDIR /app
COPY server.py index.html ./
USER 1000:1000
EXPOSE 8020
HEALTHCHECK --interval=60s --timeout=5s CMD wget -qO- http://127.0.0.1:8020/health || exit 1
CMD ["python3", "-u", "server.py"]
