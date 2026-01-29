#!/bin/bash
# Generate a simulated POTA QSO audio recording
# Two stations: W6JSV (activator) at 600Hz, N9HO (hunter) at 650Hz

set -e

OUTPUT_DIR="${1:-/tmp/pota_qso}"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "Generating CW audio files..."

# Function to generate CW audio from text
# Args: text, wpm, frequency, output_basename
generate_cw() {
    local text="$1"
    local wpm="$2"
    local freq="$3"
    local output="$4"

    echo "$text" | ebook2cw -w "$wpm" -f "$freq" -o "$output" -T 1 -
}

# Each transmission with format: "text" wpm frequency filename
# W6JSV (activator) at 600Hz, 20wpm
# N9HO (hunter) at 650Hz, 25wpm

# 1. CQ CQ POTA DE W6JSV K (W6JSV, 600Hz, 20wpm)
generate_cw "CQ CQ POTA DE W6JSV K" 20 600 "01_cq1"

# 2. CQ CQ POTA DE W6JSV K (W6JSV, 600Hz, 20wpm) - second call
generate_cw "CQ CQ POTA DE W6JSV K" 20 600 "02_cq2"

# 3. N9HO (N9HO responds, 650Hz, 25wpm)
generate_cw "N9HO" 25 650 "03_n9ho_call"

# 4. N9? (W6JSV partial copy, 600Hz, 20wpm)
generate_cw "N9?" 20 600 "04_n9q"

# 5. N9HO (N9HO repeats, 650Hz, 25wpm)
generate_cw "N9HO" 25 650 "05_n9ho_repeat"

# 6. N9HO TU ES GM UR 599 599 CA BK (W6JSV exchange, 600Hz, 20wpm)
generate_cw "N9HO TU ES GM UR 599 599 CA BK" 20 600 "06_w6jsv_exchange"

# 7. BK RR TU UR 599 599 AL AL BK (N9HO exchange, 650Hz, 25wpm)
generate_cw "BK RR TU UR 599 599 AL AL BK" 25 650 "07_n9ho_exchange"

# 8. BK RR FB TU ES 72 EE (signoff, 650Hz per user request, 20wpm)
generate_cw "BK RR FB TU ES 72 EE" 20 650 "08_signoff"

echo "Converting MP3 files to WAV..."

# Convert all mp3 files to wav (ebook2cw outputs mp3 by default with -T 1)
for mp3 in *.mp3; do
    wav="${mp3%.mp3}.wav"
    ffmpeg -y -i "$mp3" -ar 44100 -ac 1 "$wav" 2>/dev/null
done

echo "Creating silence gaps..."

# Create silence gaps (1 second between transmissions)
sox -n -r 44100 -c 1 silence_1s.wav trim 0.0 1.0

# Longer pause (2 seconds) after CQ calls
sox -n -r 44100 -c 1 silence_2s.wav trim 0.0 2.0

echo "Concatenating all files..."

# Build the final audio with appropriate gaps
sox \
    01_cq10000.wav silence_2s.wav \
    02_cq20000.wav silence_2s.wav \
    03_n9ho_call0000.wav silence_1s.wav \
    04_n9q0000.wav silence_1s.wav \
    05_n9ho_repeat0000.wav silence_1s.wav \
    06_w6jsv_exchange0000.wav silence_1s.wav \
    07_n9ho_exchange0000.wav silence_1s.wav \
    08_signoff0000.wav \
    pota_qso_raw.wav

echo "Normalizing..."

# Normalize
sox pota_qso_raw.wav pota_qso_final.wav norm -1

# Convert to mp3 for easier sharing
ffmpeg -y -i pota_qso_final.wav -b:a 192k pota_qso_final.mp3 2>/dev/null

echo ""
echo "Done! Output files:"
echo "  WAV: $OUTPUT_DIR/pota_qso_final.wav"
echo "  MP3: $OUTPUT_DIR/pota_qso_final.mp3"
echo ""
echo "QSO Summary:"
echo "  W6JSV (activator) - 600Hz @ 20wpm"
echo "  N9HO (hunter) - 650Hz @ 25wpm"
