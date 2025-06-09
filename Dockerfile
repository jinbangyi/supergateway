FROM node:22-alpine

# Install dependencies
RUN apk add --no-cache bash jq supervisor

# Install supergateway
RUN npm install -g supergateway

# Create directory for configuration files
WORKDIR /app
RUN mkdir -p /app/config

# Copy startup scripts
COPY docker-entrypoint.sh /app/
COPY parse-config.sh /app/
COPY config.sh /app/config/servers.sh

# Make scripts executable
RUN chmod +x /app/docker-entrypoint.sh /app/parse-config.sh

# Create directory for supervisor configs
RUN mkdir -p /etc/supervisor.d/ && mkdir -p /data

# Expose default ports (can be overridden by configs)
EXPOSE 8000 8001

# Set entrypoint
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default command if no arguments are provided
CMD ["--config", "/app/config/servers.sh"]
