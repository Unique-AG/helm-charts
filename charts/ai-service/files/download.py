#!/usr/bin/env python3

import sys
import requests
import os
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    force=True,
    stream=sys.stdout
)
logger = logging.getLogger('artifact-downloader')

def download_file(blob_url, dest_dir):
    try:
        filename = blob_url.split('/')[-1]
        # Ensure the path starts with /artifacts/
        full_dest_dir = os.path.join('/artifacts', dest_dir.lstrip('/'))
        full_path = os.path.join(full_dest_dir, filename)

        # Create directory if it doesn't exist
        logger.info(f"Creating directory: {full_dest_dir}")
        os.makedirs(full_dest_dir, exist_ok=True)

        # Check if file already exists
        if os.path.exists(full_path):
            logger.info(f"File already exists: {full_path}")
            return True

        # Download the file
        response = requests.get(blob_url, stream=True)
        response.raise_for_status()

        # Save the file
        with open(full_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

        logger.info(f"File downloaded successfully: {full_path}")
        return True
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to download file: {blob_url}")
        return False

# Main execution
logger.info("Starting download process")
success = True
for arg in sys.argv[1:]:
    try:
        blob_url, dest_path = arg.split(',')
        if not download_file(blob_url, dest_path):
            success = False
    except Exception as e:
        logger.error(f"Error processing argument {arg}: {str(e)}")
        success = False

sys.exit(0 if success else 1)
