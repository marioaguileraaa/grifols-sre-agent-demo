FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG REACT_APP_API_BASE_URL=http://localhost:5291/api
ENV REACT_APP_API_BASE_URL=$REACT_APP_API_BASE_URL
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN printf '%s\n' \
  '#!/bin/sh' \
  'if [ -n "$REACT_APP_API_BASE_URL" ]; then' \
  '  find /usr/share/nginx/html -name "*.js" -exec sed -i "s|http://localhost:5291/api|$REACT_APP_API_BASE_URL|g" {} \;' \
  'fi' > /docker-entrypoint.d/40-api-url.sh \
  && chmod +x /docker-entrypoint.d/40-api-url.sh
EXPOSE 80
