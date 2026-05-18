# Slim frontend image. Expects ./frontend/build to already exist (built by
# yarn workspace @highlight-run/frontend build on the host). Avoids the
# in-container yarn install which OOMs Docker Desktop on a 24GB host.
#
# Built by docker/build-frontend-native.sh -- not intended to be used directly.

FROM nginx:stable-alpine
RUN apk update && apk add --no-cache python3

LABEL org.opencontainers.image.source=https://github.com/workRemits/highlight
LABEL org.opencontainers.image.description="wRemit-built Highlight Frontend (self-hosted OAuth, native host build)"

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY backend/localhostssl/server.key /etc/ssl/private/ssl-cert.key
COPY backend/localhostssl/server.pem /etc/ssl/certs/ssl-cert.pem
COPY docker/frontend-entrypoint.py /frontend-entrypoint.py

WORKDIR /build
COPY frontend/build /build/frontend/build

CMD ["python3", "/frontend-entrypoint.py"]
