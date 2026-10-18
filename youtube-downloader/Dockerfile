FROM marcobaobao/yt-dlp-webui:latest

# Install Node.js for yt-dlp's JavaScript challenge solver (required for YouTube)
RUN apk add --no-cache nodejs

# bgutil-ytdlp-pot-provider: the yt-dlp plugin that fetches PO tokens from the bgutil-provider
# sidecar (docker#179). Pinned to the sidecar's version: the two speak one protocol.
RUN pip install --upgrade yt-dlp yt-dlp-ejs bgutil-ytdlp-pot-provider==2.0.2 --root-user-action=ignore --quiet
