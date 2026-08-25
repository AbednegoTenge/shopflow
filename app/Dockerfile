# ---- deps: install production dependencies only ----
FROM node:20-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# ---- certs: fetch the RDS CA bundle at build time (not committed to git) ----
FROM node:20-slim AS certs
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -sS -o /global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    && rm -rf /var/lib/apt/lists/*

# ---- final: minimal runtime image, non-root ----
FROM node:20-slim
WORKDIR /app

RUN groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 --gid nodejs appuser

COPY --from=deps /app/node_modules ./node_modules
COPY --from=certs /global-bundle.pem ./global-bundle.pem
COPY package.json ./
COPY server.js ./
COPY migrate.js ./
COPY src ./src

USER appuser
EXPOSE 3000
CMD ["node", "server.js"]
