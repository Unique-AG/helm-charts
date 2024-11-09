#!/bin/sh
set -e

# Install required libraries
pip install requests

# Force unbuffered Python output
export PYTHONUNBUFFERED=1

# Execute the Python script with all arguments
python3 /files/download.py "$@"
