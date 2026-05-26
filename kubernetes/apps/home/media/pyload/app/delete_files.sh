#!/bin/bash
# PyLoad passes the package download folder as the 3rd argument
DOWNLOAD_DIR="$3"

if [ "$DOWNLOAD_DIR" != "/downloads" ] && [ -n "$DOWNLOAD_DIR" ]; then
    rm -rf "$DOWNLOAD_DIR"
fi
