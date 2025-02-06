#!/bin/sh
set -e

echo "Starting artifact download process..."

download_if_missing() {
    local url=$1
    local dest_dir=$2
    
    # Ensure dest_dir starts with /artifacts/
    dest_dir="/artifacts/${dest_dir#/}"
    
    # Extract filename from URL
    local filename=$(basename "$url")
    local full_path="${dest_dir}/${filename}"
    
    # Create directory if it doesn't exist
    if ! mkdir -p "$dest_dir" 2>/dev/null; then
        echo "Error: Cannot create directory $dest_dir. Permission denied."
        return 1
    fi
    
    if [ -f "$full_path" ]; then
        echo "File already exists: $full_path"
        return 0
    fi
    
    echo "Downloading $filename to $dest_dir..."
    for i in 1 2 3; do
        if curl -sSf -o "$full_path" "$url" 2>/dev/null; then
            echo "Successfully downloaded: $full_path"
            return 0
        fi
        echo "Attempt $i failed, retrying..."
        sleep 5
    done
    
    echo "Failed to download $filename after 3 attempts"
    return 1
}

# Process all arguments
success=true
while [ $# -gt 0 ]; do
    # Split the current argument on comma
    url=$(echo "$1" | cut -d',' -f1)
    dest_path=$(echo "$1" | cut -d',' -f2)
    
    if [ -z "$url" ] || [ -z "$dest_path" ]; then
        echo "Error: Invalid argument format. Expected 'URL,destination' but got: $1"
        exit 1
    fi
    
    if ! download_if_missing "$url" "$dest_path"; then
        success=false
    fi
    shift
done

if [ "$success" = true ]; then
    exit 0
else
    exit 1
fi