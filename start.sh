#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
  echo "Environment variables from .env file successfully loaded"
else
  echo "File .env not found. Using default settings."
fi

# Start the application
echo "Starting Phoenix server..."
iex -S mix phx.server 