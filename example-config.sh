#!/bin/bash
# Example shell script configuration for Supergateway multi-server setup

# First server - filesystem server on port 8000
supergateway --stdio "npx -y @modelcontextprotocol/server-filesystem /data" \
  --port 8000 \
  --ssePath /sse/8000 \
  --messagePath /message/8000 \
  --logLevel info \
  --name filesystem-server

# Second server - another MCP server on port 8001
supergateway --stdio "npx -y @agentdeskai/browser-server@latest" \
  --port 8001 \
  --ssePath /sse/8001 \
  --messagePath /message/8001 \
  --name another-server
