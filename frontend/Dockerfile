# syntax=docker/dockerfile:1

# ---------- Builder ----------
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# Baked into the static bundle at build time. Leave empty so the app calls the
# same origin and nginx proxies /api to the Trip Service.
ARG VITE_TRIP_SERVICE_URL=""
ENV VITE_TRIP_SERVICE_URL=$VITE_TRIP_SERVICE_URL
RUN npm run build

# ---------- Runtime ----------
FROM nginx:1.27-alpine AS runtime
RUN apk add --no-cache curl
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:80/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
