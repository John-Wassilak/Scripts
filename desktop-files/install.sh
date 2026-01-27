#!/bin/bash

# Define the source directory containing your .desktop and icon files
DEST_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/128x128/apps/"

# Check if the script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." 
    exit 1
fi

# Copy .desktop files to the destination
for desktop_file in *.desktop; do
    if [[ -f "$desktop_file" ]]; then
        cp "$desktop_file" "$DEST_DIR/"
        echo "Installed: $(basename "$desktop_file")"
    fi
done

# Copy icons (if available)
for icon_file in ./icons/*; do
    if [[ -f "$icon_file" ]]; then
        cp "$icon_file" "$ICON_DIR/"
        echo "Installed icon: $(basename "$icon_file")"
    fi
done

# Update the desktop database
update-desktop-database "$DEST_DIR"

echo "Installation complete."
