#!/bin/bash

set -e  # Exit on error
#set -x  # Debug mode

# Configuration
SOURCE_DIR="examples/input"
DEST_DIR="examples/output"
LOG_FILE="compression.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check ffmpeg installation
if ! command -v ffmpeg >/dev/null 2>&1; then
    log_message "Error: ffmpeg not found. Please install ffmpeg."
    exit 1
fi

# Quality settings
IMAGE_RESOLUTION="1024x1024"
MAX_FILE_SIZE="300k"   # Maximum file size for compressed images

# Video compression settings
VIDEO_BITRATE="800k"   # Target bitrate for videos
VIDEO_SCALE="1280:720" # Target resolution for videos

# Parse arguments
RUN_IMAGE_COMPRESSION=false
RUN_VIDEO_COMPRESSION=false

while getopts "iv" opt; do
    case $opt in
        i)
            RUN_IMAGE_COMPRESSION=true
            ;;
        v)
            RUN_VIDEO_COMPRESSION=true
            ;;
        *)
            echo "Usage: $0 [-i] [-v]"
            echo "  -i    Run image compression"
            echo "  -v    Run video compression"
            exit 1
            ;;
    esac
done

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

if [ "$RUN_IMAGE_COMPRESSION" = true ]; then
    # Find and compress images
    find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | while read FILE; do
            REL_PATH="${FILE#$SOURCE_DIR/}"  
            DEST_FILE="$DEST_DIR/$REL_PATH"
            DEST_FOLDER="$(dirname "$DEST_FILE")"

            mkdir -p "$DEST_FOLDER"

            convert "$FILE" -resize ${IMAGE_RESOLUTION}\> -define jpeg:extent=$MAX_FILE_SIZE "$DEST_FILE"
            log_message "Image compressed: $DEST_FILE"
    done
fi

if [ "$RUN_VIDEO_COMPRESSION" = true ]; then
    # Set up trap for cleanup
    trap 'log_message "Interrupted - cleaning up..."; exit 1' INT TERM

    # Find and compress videos
    log_message "Compressing videos from: $SOURCE_DIR"
    find "$SOURCE_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" \) -print0 | 
    while IFS= read -r -d $'\0' FILE; do
        REL_PATH="${FILE#$SOURCE_DIR/}"
        DEST_FILE="$DEST_DIR/${REL_PATH%.*}.mp4"
        DEST_FOLDER="$(dirname "$DEST_FILE")"

        mkdir -p "$DEST_FOLDER"

        if [ -f "$DEST_FILE" ]; then
            log_message "Skipping existing file: $DEST_FILE"
            continue
        fi

        # Check input file size
        FILE_SIZE=$(stat -f %z "$FILE" 2>/dev/null || stat -c %s "$FILE")
        if [ "$FILE_SIZE" -eq 0 ]; then
            log_message "Error: Empty file $FILE"
            continue
        fi

        log_message "Processing video: $REL_PATH"
        if ffmpeg -nostdin -y -i "$FILE" \
            -vf "scale=$VIDEO_SCALE:force_original_aspect_ratio=decrease" \
            -b:v "$VIDEO_BITRATE" \
            -c:v libx264 -preset fast \
            -c:a aac -b:a 128k \
            -movflags +faststart \
            -max_muxing_queue_size 1024 \
            "$DEST_FILE" 2>"${DEST_FILE}.log"; then
            log_message "Video compressed: $DEST_FILE"
            rm -f "${DEST_FILE}.log"
        else
            log_message "Error processing: $FILE"
            cat "${DEST_FILE}.log"
            rm -f "$DEST_FILE" "${DEST_FILE}.log"
            continue
        fi
    done

    # Remove trap
    trap - INT TERM
fi