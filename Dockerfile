# The app with its small Node server (accounts and synced saves). No npm packages are needed.
FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080 DATA_DIR=/data STATIC_DIR=/app
COPY index.html privacy.html sw.js manifest.webmanifest ./
COPY icons ./icons
COPY pet ./pet
COPY bg ./bg
COPY server ./server
COPY test ./test
# A failing test stops the build, so the version already running stays up.
RUN node test/server.js && rm -rf test
RUN mkdir -p /data && chown node:node /data
USER node
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "server/main.js"]
