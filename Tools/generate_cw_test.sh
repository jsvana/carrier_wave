#!/bin/bash

# Generate CW test audio files from text
# Usage: ./generate_cw_test.sh "TEXT TO ENCODE" [wpm] [frequency] [output_name]

set -e

# Check dependencies
check_deps() {
    local missing=()

    if ! command -v ebook2cw &> /dev/null; then
        missing+=("ebook2cw")
    fi

    if ! command -v ffmpeg &> /dev/null; then
        missing+=("ffmpeg")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo "ERROR: Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install with Homebrew:"
        for dep in "${missing[@]}"; do
            echo "  brew install $dep"
        done
        exit 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0 \"TEXT\" [wpm] [frequency] [output_name]"
    echo ""
    echo "Arguments:"
    echo "  TEXT        - Text to encode as CW (required)"
    echo "  wpm         - Words per minute (default: 20)"
    echo "  frequency   - Tone frequency in Hz (default: 700)"
    echo "  output_name - Output filename without extension (default: test_cw)"
    echo ""
    echo "Examples:"
    echo "  $0 \"CQ CQ DE W1AW\""
    echo "  $0 \"CQ CQ DE W1AW\" 25 600"
    echo "  $0 \"HELLO WORLD\" 15 700 hello_test"
    echo ""
    echo "Output: Creates a 16-bit mono WAV file at 44100 Hz"
}

# Main
check_deps

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

TEXT="$1"
WPM="${2:-20}"
FREQ="${3:-700}"
OUTPUT="${4:-test_cw}"

# Create temp directory for intermediate files
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Generating CW audio..."
echo "  Text: \"$TEXT\""
echo "  WPM: $WPM"
echo "  Frequency: $FREQ Hz"
echo "  Output: ${OUTPUT}.wav"
echo ""

# Generate MP3 with ebook2cw
echo "$TEXT" | ebook2cw -w "$WPM" -f "$FREQ" -o "$TMPDIR/cw" > /dev/null 2>&1

# Convert to WAV (16-bit mono, 44100 Hz)
ffmpeg -y -i "$TMPDIR/cw0000.mp3" -ar 44100 -ac 1 -acodec pcm_s16le "${OUTPUT}.wav" -loglevel error

echo "Done! Created ${OUTPUT}.wav"
echo ""
echo "Test with:"
echo "  swift Tools/test_cw_decoder.swift ${OUTPUT}.wav $FREQ $WPM"
