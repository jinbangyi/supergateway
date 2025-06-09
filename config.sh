#!/bin/bash
# Example shell script configuration for Supergateway multi-server setup

# First server - filesystem server on port 8000
supergateway --stdio "npx -y @modelcontextprotocol/server-filesystem /data" \
  --port 8000 \
  --ssePath /sse \
  --messagePath /message \
  --logLevel info \
  --name filesystem-server

# Second server - another MCP server on port 8001
supergateway --stdio "npx -y @agentdeskai/browser-tools-server@latest" \
  --port 8001 \
  --ssePath /sse \
  --messagePath /message \
  --name another-server
