#!/bin/bash
set -e

CONFIG_PATH="$1"
SUPERVISOR_DIR="/etc/supervisor.d"
# SUPERVISOR_DIR="/home/coder/supergateway/debug"
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-localhost}"

# Function to create supervisor config for a server
create_supervisor_config() {
  local name="$1"
  local command="$2"
  
  cat > "${SUPERVISOR_DIR}/${name}.ini" << EOF
[program:${name}]
command=${command}
autostart=true
autorestart=true
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF
}

# Check file type by extension
file_extension="${CONFIG_PATH##*.}"

# Process the config based on file type
if [[ "$file_extension" == "json" ]]; then
  echo "Parsing JSON config file: $CONFIG_PATH"
  
  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required to parse JSON config but is not installed"
    exit 1
  fi
  
  # Get the number of servers
  SERVER_COUNT=$(jq '.servers | length' "$CONFIG_PATH")
  
  # Loop through each server configuration
  for (( i=0; i<$SERVER_COUNT; i++ )); do
    # Extract server configuration
    NAME=$(jq -r ".servers[$i].name // \"server$i\"" "$CONFIG_PATH")
    STDIO=$(jq -r ".servers[$i].stdio" "$CONFIG_PATH")
    PORT=$(jq -r ".servers[$i].port // 8000" "$CONFIG_PATH")
    BASE_URL=$(jq -r ".servers[$i].baseUrl // \"\"" "$CONFIG_PATH")
    SSE_PATH=$(jq -r ".servers[$i].ssePath // \"/sse\"" "$CONFIG_PATH")
    MESSAGE_PATH=$(jq -r ".servers[$i].messagePath // \"/message\"" "$CONFIG_PATH")
    CORS=$(jq -r ".servers[$i].cors // false" "$CONFIG_PATH")
    LOG_LEVEL=$(jq -r ".servers[$i].logLevel // \"info\"" "$CONFIG_PATH")
    HEALTH_ENDPOINT=$(jq -r ".servers[$i].healthEndpoint // \"\"" "$CONFIG_PATH")
    
    # Build command
    CMD="supergateway --stdio \"$STDIO\" --port $PORT"
    
    # Add optional parameters if they exist
    [[ "$BASE_URL" != "" && "$BASE_URL" != "null" ]] && CMD="$CMD --baseUrl \"$BASE_URL\""
    [[ "$SSE_PATH" != "null" ]] && CMD="$CMD --ssePath $SSE_PATH"
    [[ "$MESSAGE_PATH" != "null" ]] && CMD="$CMD --messagePath $MESSAGE_PATH"
    [[ "$CORS" == "true" ]] && CMD="$CMD --cors"
    [[ "$LOG_LEVEL" != "null" ]] && CMD="$CMD --logLevel $LOG_LEVEL"
    [[ "$HEALTH_ENDPOINT" != "" && "$HEALTH_ENDPOINT" != "null" ]] && CMD="$CMD --healthEndpoint $HEALTH_ENDPOINT"
    
    # Handle array types like headers
    if jq -e ".servers[$i].headers" "$CONFIG_PATH" > /dev/null 2>&1; then
      HEADERS_COUNT=$(jq ".servers[$i].headers | length" "$CONFIG_PATH")
      for (( j=0; j<$HEADERS_COUNT; j++ )); do
        HEADER=$(jq -r ".servers[$i].headers[$j]" "$CONFIG_PATH")
        CMD="$CMD --header \"$HEADER\""
      done
    fi
    
    # Handle oauth2Bearer if present
    OAUTH2_BEARER=$(jq -r ".servers[$i].oauth2Bearer // \"\"" "$CONFIG_PATH")
    [[ "$OAUTH2_BEARER" != "" && "$OAUTH2_BEARER" != "null" ]] && CMD="$CMD --oauth2Bearer \"$OAUTH2_BEARER\""
    
    echo "Creating supervisor config for $NAME"
    create_supervisor_config "$NAME" "$CMD"
  done
  
elif [[ "$file_extension" == "sh" ]]; then
  echo "Parsing shell script config file: $CONFIG_PATH"
  
  # Make the script executable
  chmod +x "$CONFIG_PATH"
  
  # Parse the shell script line by line, handling multi-line commands
  line_number=0
  current_command=""
  in_multiline=false
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments (but not if we're in a multi-line command)
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*#.*$ ]] && [[ "$in_multiline" == false ]]; then
      continue
    fi
    
    # Remove leading and trailing whitespace
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check if this line ends with a backslash (continuation)
    if [[ "$line" =~ \\[[:space:]]*$ ]]; then
      # Remove the backslash and add to current command
      line=$(echo "$line" | sed 's/\\[[:space:]]*$//')
      current_command="$current_command $line"
      in_multiline=true
      continue
    else
      # This is the end of the command (either single line or end of multi-line)
      current_command="$current_command $line"
      in_multiline=false
    fi
    
    # Clean up extra spaces
    current_command=$(echo "$current_command" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check if this is a supergateway command
    if [[ "$current_command" =~ ^supergateway ]]; then
      line_number=$((line_number + 1))
      
      # Extract name from command if available, otherwise use default
      if [[ "$current_command" =~ --name[[:space:]]+([[:alnum:]_-]+) ]]; then
        name="${BASH_REMATCH[1]}"
      else
        name="server$line_number"
        # Add name parameter to command
        current_command="$current_command --name $name"
      fi
      
      echo "Creating supervisor config for $name"
      create_supervisor_config "$name" "$current_command"
    fi
    
    # Reset for next command
    current_command=""
  done < "$CONFIG_PATH"
  
else
  echo "Unsupported config file format: $file_extension"
  echo "Supported formats: json, sh"
  exit 1
fi

echo "Configuration complete. Created $(ls -1 $SUPERVISOR_DIR/*.ini | wc -l) server configurations."

# Generate nginx configuration if the generate script exists
NGINX_GENERATOR="/app/generate-nginx-config.sh"
if [[ -f "$NGINX_GENERATOR" ]]; then
  echo "Generating nginx configuration..."
  
  # Create nginx config directory if it doesn't exist
  mkdir -p "$NGINX_CONF_DIR"
  
  # Generate nginx config
  if "$NGINX_GENERATOR" "$CONFIG_PATH" "$NGINX_CONF_DIR" "$DOMAIN_SUFFIX"; then
    echo "Nginx configuration generated successfully at $NGINX_CONF_DIR/supergateway.conf"
    echo ""
    echo "Hostname mappings created:"
    
    # Show the mappings
    if [[ "$file_extension" == "json" ]]; then
      if command -v jq &> /dev/null; then
        SERVER_COUNT=$(jq '.servers | length' "$CONFIG_PATH")
        for (( i=0; i<$SERVER_COUNT; i++ )); do
          NAME=$(jq -r ".servers[$i].name // \"server$i\"" "$CONFIG_PATH")
          PORT=$(jq -r ".servers[$i].port // 8000" "$CONFIG_PATH")
          echo "  - ${NAME}-mcp-server.${DOMAIN_SUFFIX} -> 127.0.0.1:${PORT}"
        done
      fi
    else
      # Parse shell script again for summary
      line_number=0
      current_command=""
      in_multiline=false
      
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*#.*$ ]] && [[ "$in_multiline" == false ]]; then
          continue
        fi
        
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ "$line" =~ \\[[:space:]]*$ ]]; then
          line=$(echo "$line" | sed 's/\\[[:space:]]*$//')
          current_command="$current_command $line"
          in_multiline=true
          continue
        else
          current_command="$current_command $line"
          in_multiline=false
        fi
        
        current_command=$(echo "$current_command" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ "$current_command" =~ ^supergateway ]]; then
          line_number=$((line_number + 1))
          
          if [[ "$current_command" =~ --name[[:space:]]+([[:alnum:]_-]+) ]]; then
            name="${BASH_REMATCH[1]}"
          else
            name="server$line_number"
          fi
          
          if [[ "$current_command" =~ --port[[:space:]]+([0-9]+) ]]; then
            port="${BASH_REMATCH[1]}"
          else
            port="8000"
          fi
          
          echo "  - ${name}-mcp-server.${DOMAIN_SUFFIX} -> 127.0.0.1:${port}"
        fi
        
        current_command=""
      done < "$CONFIG_PATH"
    fi
  else
    echo "Warning: Failed to generate nginx configuration"
  fi
else
  echo "Nginx configuration generator not found at $NGINX_GENERATOR"
fi
