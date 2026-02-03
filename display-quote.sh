#!/bin/bash

QUOTES_FILE="/home/john/quotes"

if [ ! -f "$QUOTES_FILE" ]; then
    echo "Error: Quotes file not found at $QUOTES_FILE"
    exit 1
fi

random_quote=$(shuf -n 1 "$QUOTES_FILE")

echo "Random Quote:"
echo ""
echo "$random_quote"
echo ""
