FROM node:22-alpine

# Install dependencies including nginx
RUN apk add --no-cache bash jq supervisor nginx

# Install supergateway
RUN npm install -g supergateway

# Create directory for configuration files
WORKDIR /app
RUN mkdir -p /app/config

# Copy startup scripts
COPY docker-entrypoint.sh /app/
COPY parse-config.sh /app/
COPY generate-nginx-config.sh /app/
COPY config.sh /app/config/servers.sh

# Make scripts executable
RUN chmod +x /app/docker-entrypoint.sh /app/parse-config.sh /app/generate-nginx-config.sh

# Create directory for supervisor configs
RUN mkdir -p /etc/supervisor.d/ && mkdir -p /data

# Create nginx directories and basic configuration
RUN mkdir -p /etc/nginx/conf.d /var/log/nginx /var/lib/nginx /run/nginx
RUN rm -f /etc/nginx/http.d/default.conf

# Copy nginx main configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx-supervisor.conf /etc/supervisor.d/nginx.ini

# Expose default ports (can be overridden by configs)
EXPOSE 8080
# ENV DOMAIN_SUFFIX 'localhost'

# Set entrypoint
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default command if no arguments are provided
CMD ["--config", "/app/config/servers.sh"]

# ${name}-mcp-server.localhost
# curl \
# -H "Accept: text/event-stream" \
# -H "Cache-Control: no-cache" \
# -H "Hostname: filesystem-server-mcp-server.localhost" \
# "http://localhost:8080/sse" -i
