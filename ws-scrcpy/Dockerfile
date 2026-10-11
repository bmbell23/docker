# ws-scrcpy (docker#171): Brandon's phone in a browser tab. No upstream release since
# v0.8.1 (2024) and no official image, so build a pinned upstream commit.
FROM node:18-bookworm AS build
ARG WS_SCRCPY_REF=cd6cea6ebde17af6685c2b325183fc24bef9d52b
WORKDIR /src
RUN git clone https://github.com/NetrisTV/ws-scrcpy.git . && git checkout "$WS_SCRCPY_REF"
# Upstream has no listen-address option: bind only to LISTEN_HOST (the Tailscale IP).
# The grep fails the build if upstream ever moves that line.
RUN sed -i "s|server.listen(port, () => {|server.listen(port, process.env.LISTEN_HOST \|\| '0.0.0.0', () => {|" src/server/services/HttpServer.ts \
 && grep -q "LISTEN_HOST" src/server/services/HttpServer.ts \
 && npm ci && npm run dist \
 && cd dist && npm install --omit=dev

FROM node:18-bookworm-slim
# ws-scrcpy shells out to `adb` to start its server on the phone. Debian's adb speaks
# protocol 41, same as the host's adb server (34.0.5), so it reuses that server instead
# of killing it. With network_mode: host it finds the server on 127.0.0.1:5037.
RUN apt-get update && apt-get install -y --no-install-recommends adb && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/dist /app
ENV NODE_ENV=production
CMD ["node", "index.js"]
