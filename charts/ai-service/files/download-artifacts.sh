#!/bin/sh

# Install required libraries
pip install requests

download_status=0  # A variable to track overall success/failure

# Function to download a model from blob storage and check for its existence
download_model () {
  local blobUrl=$1
  local path=$2
  local retryCount=0
  local maxRetries=3

  while [ $retryCount -lt $maxRetries ]; do
    echo "Downloading model into $path (Retry $((retryCount+1))/$maxRetries)"
    if [ -d "$path" ]; then
      echo "Model already exists in $path, skipping download"
      return 0
    fi
    if curl -L "$blobUrl" | tar -xz -C "$path"; then
      echo "Successfully downloaded model"
      return 0
    else
      echo "Error: Failed to download model, retrying..."
      retryCount=$((retryCount+1))
    fi
  done

  echo "Error: Failed to download model after $maxRetries retries."
  return 1
}

# Download models from blob storage
for modelDownload in "$@"; do
  blobUrl=$(echo "$modelDownload" | cut -d ',' -f1)
  path=$(echo "$modelDownload" | cut -f2)
  if ! download_model "$blobUrl" "$path"; then
    download_status=1
  fi
done

# Check if any downloads failed
if [ $download_status -ne 0 ]; then
  echo "Warning: Some models failed to download, continuing with the rest."
else
  echo "All models downloaded successfully."
fi