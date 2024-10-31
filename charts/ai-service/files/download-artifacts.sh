#!/bin/sh

# Install required libraries
pip install requests

download_status=0  # A variable to track overall success/failure

# Function to download a file from blob storage and check for its existence
download_model () {
  local blobUrl=$1
  local destDir=$2
  local retryCount=0
  local maxRetries=3

  # Extract filename from URL
  local filename=$(basename "$blobUrl")
  local fullPath="$destDir/$filename"

  # Create directory if it doesn't exist
  echo "Creating directory: $destDir"
  mkdir -p "$destDir"

  while [ $retryCount -lt $maxRetries ]; do
    echo "Downloading $filename into $fullPath (Retry $((retryCount+1))/$maxRetries)"
    if [ -f "$fullPath" ]; then
      echo "File already exists at $fullPath, skipping download"
      return 0
    fi
    if curl -L "$blobUrl" -o "$fullPath"; then
      echo "Successfully downloaded $filename"
      return 0
    else
      echo "Error: Failed to download $filename, retrying..."
      retryCount=$((retryCount+1))
    fi
  done

  echo "Error: Failed to download $filename after $maxRetries retries."
  return 1
}

# Download models from blob storage
for modelDownload in "$@"; do
  blobUrl=$(echo "$modelDownload" | cut -d ',' -f1)
  destDir=$(echo "$modelDownload" | cut -d ',' -f2)
  if ! download_model "$blobUrl" "$destDir"; then
    download_status=1
  fi
done

# Check if any downloads failed
if [ $download_status -ne 0 ]; then
  echo "Warning: Some files failed to download, continuing with the rest."
else
  echo "All files downloaded successfully."
fi