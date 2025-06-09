#!/bin/bash
set -e

# Function to show usage
show_usage() {
  echo "Usage: docker run <image> --config <path_to_config>"
  echo ""
  echo "The config file can be either:"
  echo "  - A JSON file with server configurations"
  echo "  - A shell script with multiple supergateway commands"
  echo ""
  echo "Example JSON format:"
  echo '{
  "servers": [
    {
      "name": "server1",
      "stdio": "npx -y @modelcontextprotocol/server-filesystem /data1",
      "port": 8000,
      "ssePath": "/sse1",
      "messagePath": "/message1",
      "cors": true
    },
    {
      "name": "server2",
      "stdio": "npx -y @modelcontextprotocol/server-filesystem /data2",
      "port": 8001,
      "ssePath": "/sse2",
      "messagePath": "/message2"
    }
  ]
}'
  echo ""
  echo "Example shell script format:"
  echo '#!/bin/bash'
  echo 'supergateway --stdio "npx -y @modelcontextprotocol/server-filesystem /data1" --port 8000 --ssePath /sse1 --messagePath /message1 --name server1'
  echo 'supergateway --stdio "npx -y @modelcontextprotocol/server-filesystem /data2" --port 8001 --ssePath /sse2 --messagePath /message2 --name server2'
  echo ""
}

# Handle special cases
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_usage
  exit 0
fi

# Check if we're using a config file
if [[ "$1" == "--config" && -n "$2" ]]; then
  CONFIG_PATH="$2"
  
  # Check if config file exists
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Error: Config file $CONFIG_PATH not found"
    exit 1
  fi
  
  # Parse the config file and create supervisor configs
  /app/parse-config.sh "$CONFIG_PATH"
  
  # Start supervisor to manage multiple processes
  exec supervisord -n
else
  # If no config specified, run supergateway directly with passed arguments
  exec supergateway "$@"
fi
