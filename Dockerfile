# Build the browser bundles and keep the TypeScript runtime used by the authoritative server.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY . .
ARG VITE_KR_PLAYTEST=0
ARG DEPLOY_BASE=/
ARG VITE_KR_SHA=unknown
ARG VITE_KR_CHANNEL=next
ARG VITE_KR_TAG=
RUN VITE_KR_PLAYTEST="$VITE_KR_PLAYTEST" DEPLOY_BASE="$DEPLOY_BASE" \
    VITE_KR_SHA="$VITE_KR_SHA" VITE_KR_CHANNEL="$VITE_KR_CHANNEL" VITE_KR_TAG="$VITE_KR_TAG" npm run build

FROM node:22-bookworm-slim AS runtime
LABEL org.opencontainers.image.source="https://github.com/CyberSt0rm1/kongroyale" \
      org.opencontainers.image.description="Self-hosted Kong Royale with private rooms" \
      org.opencontainers.image.licenses="MIT"
WORKDIR /app
ENV NODE_ENV=production KR_SERVE=1 KR_HOST=0.0.0.0 KR_PORT=3020 KR_EVENT_MODE=0
# tsx is a devDependency upstream, so production-only installs cannot run this server.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json /app/package-lock.json /app/tsconfig.json ./
COPY --from=build /app/server ./server
COPY --from=build /app/shared ./shared
COPY --from=build /app/dist ./dist
COPY --from=build /app/dist-admin ./dist-admin
COPY --from=build /app/public/assets/terrain/island.bin ./public/assets/terrain/island.bin
COPY --from=build /app/public/assets/veg/spawn-mask.bin ./public/assets/veg/spawn-mask.bin
COPY --from=build /app/tools/admin-lobby/key.mjs ./tools/admin-lobby/key.mjs
COPY --from=build /app/LICENSE /app/CREDITS.md ./
RUN mkdir -p /app/.kongbot && chown node:node /app/.kongbot
USER node
EXPOSE 3020
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.KR_PORT||3020)+'/health',{signal:AbortSignal.timeout(4000)}).then(async r=>{if(!r.ok||!(await r.json()).ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node", "--import", "tsx", "server/index.ts"]
