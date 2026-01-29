import SwiftUI

// MARK: - CWSettingsMenu

/// Settings menu content for CW transcription view
struct CWSettingsMenu: View {
    // MARK: Internal

    @ObservedObject var service: CWTranscriptionService

    var body: some View {
        wpmSection
        frequencySection
        signalSection
    }

    // MARK: Private

    // MARK: - WPM Section

    private var wpmSection: some View {
        Section("WPM") {
            ForEach([15, 20, 25, 30], id: \.self) { wpm in
                Button {
                    service.setWPM(wpm)
                } label: {
                    HStack {
                        Text("\(wpm) WPM")
                        Spacer()
                        if service.estimatedWPM == wpm {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Frequency Section

    private var frequencySection: some View {
        Section("Frequency") {
            Button {
                service.adaptiveFrequencyEnabled.toggle()
            } label: {
                HStack {
                    Text("Auto-Detect")
                    Spacer()
                    if service.adaptiveFrequencyEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if service.adaptiveFrequencyEnabled {
                adaptiveFrequencyPresets
            } else {
                fixedFrequencyPresets
            }
        }
    }

    private var adaptiveFrequencyPresets: some View {
        Group {
            Button {
                service.minFrequency = 400
                service.maxFrequency = 900
            } label: {
                HStack {
                    Text("Wide (400-900 Hz)")
                    Spacer()
                    if service.minFrequency == 400, service.maxFrequency == 900 {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                service.minFrequency = 500
                service.maxFrequency = 800
            } label: {
                HStack {
                    Text("Normal (500-800 Hz)")
                    Spacer()
                    if service.minFrequency == 500, service.maxFrequency == 800 {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                service.minFrequency = 550
                service.maxFrequency = 700
            } label: {
                HStack {
                    Text("Narrow (550-700 Hz)")
                    Spacer()
                    if service.minFrequency == 550, service.maxFrequency == 700 {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private var fixedFrequencyPresets: some View {
        ForEach([600, 700, 800], id: \.self) { freq in
            Button {
                service.toneFrequency = Double(freq)
            } label: {
                HStack {
                    Text("\(freq) Hz")
                    Spacer()
                    if Int(service.toneFrequency) == freq {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    // MARK: - Signal Section

    private var signalSection: some View {
        Section("Signal") {
            Button {
                service.preAmpEnabled.toggle()
            } label: {
                HStack {
                    Text("Pre-Amp (10x)")
                    Spacer()
                    if service.preAmpEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}
