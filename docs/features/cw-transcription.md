# CW Transcription

Real-time CW (Morse code) audio decoding from device microphone.

## Architecture

### Pipeline Overview

```
Microphone → Audio Capture → Signal Processor → Morse Decoder → UI
                                    ↓
                           ┌───────┴───────┐
                           ↓               ↓
                    Bandpass Filter   Level Meter
                           ↓
                    Envelope Follower
                           ↓
                    Adaptive Threshold
                           ↓
                      Key Events
```

### Components

| Component | File | Purpose |
|-----------|------|---------|
| CWAudioCapture | `Services/CWAudioCapture.swift` | AVAudioEngine microphone capture, outputs `AsyncStream<AudioBuffer>` |
| CWSignalProcessor | `Services/CWSignalProcessor.swift` | DSP pipeline: filter → envelope → threshold → key events |
| MorseDecoder | `Services/MorseDecoder.swift` | Timing state machine, classifies dits/dahs, outputs characters |
| MorseCode | `Services/MorseCode.swift` | Lookup tables, timing constants, abbreviations |
| CallsignDetector | `Services/CallsignDetector.swift` | Regex-based callsign extraction from transcript |
| CWTranscriptionService | `Services/CWTranscriptionService.swift` | Coordinates all components, publishes state for UI |

## Signal Processing Details

### 1. Audio Capture (`CWAudioCapture`)

- Uses `AVAudioEngine` with input node tap
- Sample rate: 44100 Hz (standard)
- Buffer size: 1024 frames (~23ms latency)
- Outputs `AsyncStream<AudioBuffer>` with samples + timestamps
- Requires `NSMicrophoneUsageDescription` in Info.plist

### 2. Bandpass Filter (`BiquadFilter`)

Digital biquad bandpass filter isolates CW tone from noise.

**Parameters:**
- Center frequency: Configurable (default 600 Hz, typical CW sidetone)
- Q factor: 2.0 (wider passband for tolerance to frequency drift)
- Uses Audio EQ Cookbook formulas for coefficient calculation

**Implementation:** Direct Form II Transposed for numerical stability.

### 3. Envelope Follower (`EnvelopeFollower`)

Extracts amplitude envelope from filtered signal.

**Parameters:**
- Attack time: ~5ms (fast rise to catch tone onset)
- Decay time: ~20ms (slower fall to smooth gaps within characters)
- Outputs rectified, smoothed amplitude values

### 4. Adaptive Threshold (`AdaptiveThreshold`)

Detects key-down/key-up transitions from envelope.

**Algorithm:**
1. Track `noiseFloor` (decays toward quiet level)
2. Track `signalPeak` (fast attack, slow decay)
3. Calculate signal-to-noise ratio: `sample / noiseFloor`
4. Key DOWN when ratio > 2.0x
5. Key UP when ratio < 1.3x
6. Hysteresis prevents chatter at threshold boundary

**Calibration:**
- First 100 samples used for calibration (no detection)
- Noise floor starts high (1.0) and decays toward actual quiet level
- UI shows "Calibrating..." during this period

**Output:** Array of `(isDown: Bool, timestamp: TimeInterval)` events

### 5. Level Meter Normalization

Peak amplitude is normalized for UI display:
- Track running maximum of envelope values
- Normalize current peak to 0-1 range: `peak / runningMax`
- Running max decays slowly (0.9999) to adapt to level changes

## Morse Decoding

### Timing Classification (`MorseDecoder`)

Standard Morse timing (PARIS standard):
- Dit = 1 unit
- Dah = 3 units
- Element gap (within character) = 1 unit
- Character gap = 3 units
- Word gap = 7 units

**Classification thresholds:**
- Dit vs Dah: 2 units (with tolerance)
- Element vs Character gap: 2 units
- Character vs Word gap: 5 units

### Adaptive WPM

WPM estimated from measured element durations:
1. Collect recent dit/dah durations
2. Calculate implied unit duration for each
3. Use median for robustness against outliers
4. Smooth with exponential moving average
5. Clamp to valid range (5-60 WPM)

Formula: `unitDuration = 1.2 / WPM` seconds (PARIS standard)

### Character Lookup (`MorseCode`)

Static dictionary mapping Morse patterns to characters:
- Letters: `.-` → A, `-...` → B, etc.
- Numbers: `.----` → 1, `..---` → 2, etc.
- Punctuation: `.-.-.-` → `.`, `--..--` → `,`, etc.
- Prosigns: `-.-.-` → `<CT>`, `.-.-` → `<AA>`, etc.

Unknown patterns output as `[pattern]` for debugging.

## UI Components

### CWTranscriptionView

Main container with:
- Status bar (Ready/Calibrating/Listening indicator)
- Settings controls (WPM slider, Tone frequency slider)
- Waveform visualization
- Level meter (segmented bar)
- Transcript area
- Detected callsign bar
- Control buttons (Start/Stop, Copy, Clear)

### CWLevelMeter

12-segment horizontal bar showing input level:
- Red segments (0-20%): Too quiet
- Yellow/olive (20-50%): Low signal
- Green (50-80%): Good signal level
- Teal/blue (80-100%): High signal
- Unlit segments shown at 25% opacity

### CWWaveformView

Scrolling bar chart visualization:
- 32 bars showing recent envelope samples
- Green when signal detected, gray otherwise
- Updates in real-time from `waveformSamples`

## Data Flow

```
1. CWAudioCapture.startCapture() → AsyncStream<AudioBuffer>

2. For each buffer:
   CWSignalProcessor.process(samples, timestamp) → CWSignalResult
   ├── keyEvents: [(isDown, timestamp)]
   ├── peakAmplitude: Float (normalized 0-1)
   ├── isKeyDown: Bool
   ├── envelopeSamples: [Float]
   └── isCalibrating: Bool

3. For each key event:
   MorseDecoder.processKeyEvent(isKeyDown, timestamp) → [DecodedOutput]
   ├── .character(String) → append to transcript
   ├── .wordSpace → append space
   └── .element(MorseElement) → (debugging only)

4. Timeout checker (100ms interval):
   MorseDecoder.checkTimeout(currentTime) → [DecodedOutput]
   └── Flushes pending character if silence > 5 units

5. UI updates via @Published properties:
   - state: .idle | .listening | .error
   - isCalibrating: Bool
   - estimatedWPM: Int
   - peakAmplitude: Float
   - isKeyDown: Bool
   - waveformSamples: [Float]
   - transcript: [CWTranscriptEntry]
   - currentLine: String
   - detectedCallsign: DetectedCallsign?
```

## Debugging

### Logging (temporary)

Debug print statements at key points:
- `[CW] Calibrating: N/100` - calibration progress with noise/peak values
- `[CW] Buffer:` - periodic buffer stats (every 500 samples)
- `[CW] Key DOWN/UP` - state transitions with signal ratio
- `[CW] Tone ended: DIT/DAH` - element classification with duration
- `[CW] Gap ended:` - gap classification
- `[CW] Decoded:` - pattern → character mapping
- `[CW] Service received:` - characters reaching UI

### Common Issues

**Level meter not moving:**
- Check microphone permission granted
- Verify audio session is active
- Check `peakAmplitude` normalization (runningMax tracking)

**No key events detected:**
- Signal too weak relative to noise floor
- Tone frequency mismatch (adjust slider to match sidetone)
- Calibration not complete (wait for "Listening" status)

**Characters not decoding:**
- Key events happening but gaps not long enough for character flush
- Check timeout checker is running
- Verify `currentPattern` accumulating elements

**Wrong characters decoded:**
- WPM mismatch (manual override may help)
- Timing thresholds need adjustment for sender's fist

**Characters splitting apart (Goertzel backend):**
- Known issue: Manual WPM setting not fully respected yet
- Adaptive WPM may override user setting, causing timing drift
- Gap thresholds become too short, treating intra-character gaps as character gaps
- Workaround: None currently; investigation ongoing

## Configuration

### User-Adjustable Settings

| Setting | Range | Default | Purpose |
|---------|-------|---------|---------|
| WPM | 5-50 | 20 | Manual WPM override (also adaptive) |
| Tone Frequency | 400-1000 Hz | 600 Hz | Bandpass filter center frequency |

### Internal Constants

| Constant | Value | Location |
|----------|-------|----------|
| Buffer size | 1024 frames | CWAudioCapture |
| Filter Q | 2.0 | CWSignalProcessor |
| Attack time | 5ms | EnvelopeFollower |
| Decay time | 20ms | EnvelopeFollower |
| On threshold | 2.0x noise | AdaptiveThreshold |
| Off threshold | 1.3x noise | AdaptiveThreshold |
| Calibration samples | 100 | AdaptiveThreshold |
| Char timeout | 5 units | MorseDecoder |

## Future Improvements

- [ ] Audio recording/playback for practice
- [ ] Confidence indicator for decoded characters
- [ ] Haptic feedback on key-down
- [ ] POTA activation integration (pre-fill callsign)
- [ ] Session persistence
- [ ] iPad layout optimization
