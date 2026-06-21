FROM marcobaobao/yt-dlp-webui:latest

# Install Node.js for yt-dlp's JavaScript challenge solver (required for YouTube)
RUN apk add --no-cache nodejs

RUN pip install --upgrade yt-dlp yt-dlp-ejs --root-user-action=ignore --quiet
