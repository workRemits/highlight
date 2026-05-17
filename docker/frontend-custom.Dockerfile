# Custom frontend build for self-hosted Highlight on wRemit infra.
# Replaces docker/frontend.Dockerfile which hard-depends on Doppler.
# OAuth client IDs flow in as build args -> ENV -> Vite picks them up via import.meta.env.

FROM --platform=$BUILDPLATFORM node:lts-alpine AS frontend-build

RUN apk update && apk add --no-cache build-base curl python3

WORKDIR /highlight

# Cache deps first
COPY .npmignore .prettierrc .prettierignore graphql.config.js tsconfig.json turbo.json .yarnrc.yml package.json yarn.lock ./
COPY .yarn/patches ./.yarn/patches
COPY .yarn/releases ./.yarn/releases
COPY docs-content/package.json ./docs-content/package.json
COPY e2e ./e2e
COPY frontend/package.json ./frontend/package.json
COPY highlight.io/package.json ./highlight.io/package.json
COPY packages ./packages
COPY render/package.json ./render/package.json
COPY rrweb ./rrweb
COPY scripts/package.json ./scripts/package.json
COPY sdk/highlight-apollo/package.json ./sdk/highlight-apollo/package.json
COPY sdk/highlight-chrome/package.json ./sdk/highlight-chrome/package.json
COPY sdk/highlight-cloudflare/package.json ./sdk/highlight-cloudflare/package.json
COPY sdk/highlight-hono/package.json ./sdk/highlight-hono/package.json
COPY sdk/highlight-nest/package.json ./sdk/highlight-nest/package.json
COPY sdk/highlight-next/package.json ./sdk/highlight-next/package.json
COPY sdk/highlight-node/package.json ./sdk/highlight-node/package.json
COPY sdk/highlight-react/package.json ./sdk/highlight-react/package.json
COPY sdk/highlight-remix/package.json ./sdk/highlight-remix/package.json
COPY sdk/highlight-run/package.json ./sdk/highlight-run/package.json
COPY sdk/highlightinc-highlight-datasource/package.json ./sdk/highlightinc-highlight-datasource/package.json
COPY sdk/pino/package.json ./sdk/pino/package.json
COPY sourcemap-uploader/package.json ./sourcemap-uploader/package.json
RUN yarn install --immutable

COPY backend/localhostssl ./backend/localhostssl
COPY backend/private-graph ./backend/private-graph
COPY backend/public-graph ./backend/public-graph
COPY blog-content ./blog-content
COPY docs-content ./docs-content
COPY frontend ./frontend
COPY highlight.io ./highlight.io
COPY packages ./packages
COPY render ./render
COPY rrweb ./rrweb
COPY scripts ./scripts
COPY sdk ./sdk
COPY sourcemap-uploader ./sourcemap-uploader

# Build-time OAuth client IDs. Empty values are fine -- Vite just bakes "" into
# the bundle and the corresponding integration button will simply not work.
ARG SLACK_CLIENT_ID=""
ARG LINEAR_CLIENT_ID=""
ARG GITHUB_CLIENT_ID=""
ARG JIRA_CLIENT_ID=""
ARG DISCORD_CLIENT_ID=""
ARG CLICKUP_CLIENT_ID=""
ARG GITLAB_CLIENT_ID=""
ARG HEIGHT_CLIENT_ID=""
ARG MICROSOFT_TEAMS_BOT_ID=""

ENV SLACK_CLIENT_ID=$SLACK_CLIENT_ID
ENV LINEAR_CLIENT_ID=$LINEAR_CLIENT_ID
ENV GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
ENV JIRA_CLIENT_ID=$JIRA_CLIENT_ID
ENV DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID
ENV CLICKUP_CLIENT_ID=$CLICKUP_CLIENT_ID
ENV GITLAB_CLIENT_ID=$GITLAB_CLIENT_ID
ENV HEIGHT_CLIENT_ID=$HEIGHT_CLIENT_ID
ENV MICROSOFT_TEAMS_BOT_ID=$MICROSOFT_TEAMS_BOT_ID

# Placeholder values that the runtime entrypoint script replaces at container start
ENV REACT_APP_AUTH_MODE=firebase
ENV REACT_APP_FRONTEND_URI=https://app.highlight.io
ENV REACT_APP_PRIVATE_GRAPH_URI=https://pri.highlight.io
ENV REACT_APP_PUBLIC_GRAPH_URI=https://pub.highlight.io
ENV REACT_APP_OTLP_ENDPOINT=https://otel.highlight.io:4318
ENV REACT_APP_DISABLE_ANALYTICS=false

ENV NODE_OPTIONS="--max-old-space-size=16384 --openssl-legacy-provider"
RUN yarn workspace @highlight-run/frontend build

# Runtime image
FROM nginx:stable-alpine AS frontend-prod
RUN apk update && apk add --no-cache python3
LABEL org.opencontainers.image.source=https://github.com/workRemits/highlight
LABEL org.opencontainers.image.description="wRemit-built Highlight Frontend (self-hosted OAuth)"

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY backend/localhostssl/server.key /etc/ssl/private/ssl-cert.key
COPY backend/localhostssl/server.pem /etc/ssl/certs/ssl-cert.pem
COPY docker/frontend-entrypoint.py /frontend-entrypoint.py

WORKDIR /build
COPY --from=frontend-build /highlight/frontend/build /build/frontend/build

CMD ["python3", "/frontend-entrypoint.py"]
