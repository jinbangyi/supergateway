#!/bin/bash
# Generate nginx configuration for routing hostnames to different ports based on supergateway config

set -e

CONFIG_PATH="$1"
NGINX_CONF_DIR="${2:-/etc/nginx/conf.d}"
DOMAIN_SUFFIX="${3:-localhost}"

if [[ -z "$CONFIG_PATH" ]]; then
    echo "Usage: $0 <config_path> [nginx_conf_dir] [domain_suffix]"
    echo "Example: $0 config.sh /etc/nginx/conf.d localhost"
    exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Error: Config file $CONFIG_PATH not found"
    exit 1
fi

# Function to create nginx server block for a server
create_nginx_server_block() {
    local name="$1"
    local port="$2"
    local hostname="${name}-mcp-server.${DOMAIN_SUFFIX}"
    
    cat << EOF
server {
    listen 8080;
    server_name ${hostname};

    # Root location
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Add CORS headers if needed
    # add_header Access-Control-Allow-Origin '*' always;
    # add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS' always;
    # add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    # add_header Access-Control-Expose-Headers 'Content-Length,Content-Range' always;
    # 
    # # Handle preflight requests
    # if (\$request_method = 'OPTIONS') {
    #     add_header Access-Control-Allow-Origin '*';
    #     add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
    #     add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
    #     add_header Access-Control-Max-Age 1728000;
    #     add_header Content-Type 'text/plain; charset=utf-8';
    #     add_header Content-Length 0;
    #     return 204;
    # }
}

EOF
}

# Initialize output file
OUTPUT_FILE="${NGINX_CONF_DIR}/supergateway.conf"
echo "# Auto-generated nginx configuration for supergateway" > "$OUTPUT_FILE"
echo "# Generated from: $CONFIG_PATH" >> "$OUTPUT_FILE"
echo "# Generated at: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

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
        PORT=$(jq -r ".servers[$i].port // 8000" "$CONFIG_PATH")
        
        echo "Creating nginx config for $NAME on port $PORT"
        create_nginx_server_block "$NAME" "$PORT" >> "$OUTPUT_FILE"
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
            fi
            
            # Extract port from command if available, otherwise use default
            if [[ "$current_command" =~ --port[[:space:]]+([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
            else
                port="8000"
            fi
            
            echo "Creating nginx config for $name on port $port"
            create_nginx_server_block "$name" "$port" >> "$OUTPUT_FILE"
        fi
        
        # Reset for next command
        current_command=""
    done < "$CONFIG_PATH"
    
else
    echo "Unsupported config file format: $file_extension"
    echo "Supported formats: json, sh"
    exit 1
fi

echo ""
echo "Nginx configuration generated successfully:"
echo "  Output file: $OUTPUT_FILE"
echo ""
echo "Server configurations created:"

# Show summary of what was created
if [[ "$file_extension" == "json" ]]; then
    SERVER_COUNT=$(jq '.servers | length' "$CONFIG_PATH")
    for (( i=0; i<$SERVER_COUNT; i++ )); do
        NAME=$(jq -r ".servers[$i].name // \"server$i\"" "$CONFIG_PATH")
        PORT=$(jq -r ".servers[$i].port // 8000" "$CONFIG_PATH")
        echo "  - ${NAME}-mcp-server.${DOMAIN_SUFFIX} -> 127.0.0.1:${PORT}"
    done
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

echo ""
echo "To apply the configuration:"
echo "  1. Copy the generated config to your nginx configuration directory"
echo "  2. Test the configuration: sudo nginx -t"
echo "  3. Reload nginx: sudo nginx -s reload"
echo ""
echo "Make sure your DNS is configured to point the hostnames to your server."
