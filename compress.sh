#!/bin/bash

set -e  # Exit on error
#set -x  # Debug mode

# Configuration
CONFIG_FILE="compress.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "${CONFIG_FILE}" << EOL
SOURCE_DIR="examples/input"
DEST_DIR="examples/output"
LOG_FILE="compression.log"
EOL
    echo "Error: Config file not found at $CONFIG_FILE"
    echo "A config file has been created at ${CONFIG_FILE}"
    echo "Please edit it e.g.: vi ${CONFIG_FILE}"
    echo "Update file locations"
    exit 1
fi

source "$CONFIG_FILE"

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

if [ $# -eq 0 ]; then
    echo "Error: No arguments provided"
    echo "Usage: $0 [-i] [-v]"
    echo "  -i    Run image compression"
    echo "  -v    Run video compression"
    exit 1
fi

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

if [ "$RUN_IMAGE_COMPRESSION" = false ] && [ "$RUN_VIDEO_COMPRESSION" = false ]; then
    echo "Error: Must specify either -i for image compression or -v for video compression"
    echo "Usage: $0 [-i] [-v]"
    exit 1
fi

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

if [ "$RUN_IMAGE_COMPRESSION" = true ]; then
    # Find and compress images
    find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | while read FILE; do
            # Get relative path by removing source dir and leading slash
            REL_PATH="${FILE#$SOURCE_DIR}"
            REL_PATH="${REL_PATH#/}"
            
            DEST_FILE="$DEST_DIR/$REL_PATH"
            DEST_FOLDER="$(dirname "$DEST_FILE")"

            mkdir -p "$DEST_FOLDER"
            log_message "Creating directory: $DEST_FOLDER"

            # Validate image file
            if ! identify "$FILE" >/dev/null 2>&1; then
                log_message "Error: Invalid or corrupted image file: $FILE"
                continue
            fi

            # Attempt conversion with error handling
            if ! convert "$FILE" -resize ${IMAGE_RESOLUTION}\> -define jpeg:extent=$MAX_FILE_SIZE "$DEST_FILE" 2>/tmp/convert_error; then
                ERROR_MSG=$(cat /tmp/convert_error)
                log_message "Error converting $FILE: $ERROR_MSG"
                continue
            fi
            
            log_message "Image compressed: $REL_PATH"
    done
fi

if [ "$RUN_VIDEO_COMPRESSION" = true ]; then
    # Set up trap for cleanup
    trap 'log_message "Interrupted - cleaning up..."; exit 1' INT TERM

    # Find and compress videos
    log_message "Compressing videos from: $SOURCE_DIR"
    find "$SOURCE_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" \) -print0 | 
    while IFS= read -r -d $'\0' FILE; do
            # Get relative path by removing source dir and leading slash
            REL_PATH="${FILE#$SOURCE_DIR}"
            REL_PATH="${REL_PATH#/}"
            
            DEST_FILE="$DEST_DIR/$REL_PATH"
            DEST_FILE="${DEST_FILE%.*}.mp4"  # Force .mp4 extension
            DEST_FOLDER="$(dirname "$DEST_FILE")"

            mkdir -p "$DEST_FOLDER"
            log_message "Creating directory: $DEST_FOLDER"

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