
//
//  ContentView.swift
//  AIAssistant
//
//  Main UI for voice assistant with Claude AI integration and VOX support
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var claudeService: ClaudeService
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var ttsService = TextToSpeechService()
    
    @State private var isRecording = false
    @State private var recognizedText = ""
    @State private var responseText = ""
    @State private var isEnglish = true
    @State private var micVolume: Double = 1.0
    @State private var speechVolume: Double = 1.0
    @State private var voxSensitivity: Double = 0.25
    @State private var enableClaude = false
    @State private var enableVOX = false
    @State private var maxWords = 20
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentRecognitionLanguage: String = "tr-TR" // Tanıma yapılan dil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Audio Level Indicator
                AudioLevelView(level: audioManager.audioLevel)
                    .frame(height: 50)
                    .padding(.horizontal)
                
                // VOX Status Indicator
                if enableVOX {
                    voxStatusView
                }
                
                // Text Display Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !recognizedText.isEmpty {
                            textBubble(text: recognizedText, isUser: true)
                        }
                        
                        if !responseText.isEmpty {
                            textBubble(text: responseText, isUser: false)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Controls
                controlsView
                
                // Volume Sliders
                slidersView
                
                // VOX Toggle
                voxToggleView
                
                // Claude AI Toggle
                claudeToggleView
                
                Spacer()
                
                // Action Buttons
                actionButtonsView
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            setupServices()
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("Voice Assistant")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: toggleLanguage) {
                Text(isEnglish ? "🇺🇸 EN" : "🇹🇷 TR")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private var voxStatusView: some View {
        HStack {
            Circle()
                .fill(audioManager.isVOXActive ? (audioManager.isRecording ? Color.red : Color.green) : Color.gray)
                .frame(width: 12, height: 12)
            
            Text(audioManager.isVOXActive ? (audioManager.isRecording ? "VOX: Recording..." : "VOX: Listening...") : "VOX: Inactive")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    private var controlsView: some View {
        HStack(spacing: 20) {
            // Record Button
            Button(action: toggleRecord) {
                VStack {
                    Image(systemName: buttonImageName)
                        .font(.system(size: 60))
                        .foregroundColor(buttonColor)
                    
                    Text(buttonText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(ttsService.isSpeaking)
        }
    }
    
    private var buttonImageName: String {
        if enableVOX {
            return audioManager.isVOXActive ? "stop.circle.fill" : "ear.fill"
        } else {
            return isRecording ? "stop.circle.fill" : "mic.circle.fill"
        }
    }
    
    private var buttonColor: Color {
        if enableVOX {
            return audioManager.isVOXActive ? .red : .green
        } else {
            return isRecording ? .red : .blue
        }
    }
    
    private var buttonText: String {
        if enableVOX {
            return audioManager.isVOXActive ? "Stop VOX" : "Start VOX"
        } else {
            return isRecording ? "Recording..." : "Tap to Record"
        }
    }
    
    private var slidersView: some View {
        VStack(spacing: 15) {
            // Microphone Volume
            VStack(alignment: .leading) {
                Text("Microphone Volume: \(Int(micVolume * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $micVolume, in: 0...1)
                    .onChange(of: micVolume) { _, newValue in
                        audioManager.setMicrophoneVolume(newValue)
                    }
            }
            
            // Speech Volume
            VStack(alignment: .leading) {
                Text("Speech Volume: \(Int(speechVolume * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $speechVolume, in: 0...1)
                    .onChange(of: speechVolume) { _, newValue in
                        ttsService.setVolume(Float(newValue))
                    }
            }
            
            // VOX Sensitivity
            VStack(alignment: .leading) {
                Text("VOX Sensitivity: \(Int(voxSensitivity * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $voxSensitivity, in: 0...1)
                    .onChange(of: voxSensitivity) { _, newValue in
                        audioManager.voxSensitivity = newValue
                    }
            }
        }
        .padding(.horizontal)
    }
    
    private var voxToggleView: some View {
        VStack(spacing: 10) {
            Toggle("Enable VOX Mode", isOn: $enableVOX)
                .padding(.horizontal)
                .onChange(of: enableVOX) { _, newValue in
                    if !newValue && audioManager.isVOXActive {
                        audioManager.stopVOXMode()
                        speechService.stopRecording()
                    }
                }
            
            if enableVOX {
                Text("VOX will automatically start recording when it detects sound above the threshold.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var claudeToggleView: some View {
        VStack(spacing: 10) {
            Toggle("Enable Claude AI", isOn: $enableClaude)
                .padding(.horizontal)
                .onChange(of: enableClaude) { _, newValue in
                    // Claude toggle edildiğinde çeviri ayarını güncelle
                    updateTranslationSetting()
                }
            
            if enableClaude {
                HStack {
                    Text("Max Words:")
                        .font(.caption)
                    
                    Stepper("\(maxWords)", value: $maxWords, in: 10...200, step: 10)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 20) {
            Button(action: clearText) {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    // MARK: - Helper Methods
    
    private func textBubble(text: String, isUser: Bool) -> some View {
        HStack {
            if !isUser { Spacer() }
            
            Text(text)
                .padding()
                .background(isUser ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                .cornerRadius(10)
                .frame(maxWidth: 280, alignment: isUser ? .leading : .trailing)
            
            if isUser { Spacer() }
        }
    }
    
    private func setupServices() {
        speechService.onRecognition = { text, language in
            self.recognizedText = text
            self.currentRecognitionLanguage = language
            self.handleRecognizedText(text, language: language)
        }
        
        speechService.onError = { error in
            errorMessage = error
            showError = true
        }
        
        claudeService.onResponse = { response in
            responseText = response
            // Claude'ın yanıtını konuştuğumuz dilde seslendir
            speakResponse(response, language: self.currentRecognitionLanguage)
        }
        
        claudeService.onError = { error in
            errorMessage = error
            showError = true
        }
        
        // VOX callbacks
        audioManager.onVOXRecordingStarted = handleVOXRecordingStarted
        audioManager.onVOXRecordingStopped = handleVOXRecordingStopped
        
        // TTS callbacks - VOX'u pause/resume et
        ttsService.onSpeechStarted = {
            if self.enableVOX {
                self.audioManager.pauseVOX()
                print("🔇 TTS started - VOX paused")
            }
        }
        
        ttsService.onSpeechFinished = {
            if self.enableVOX {
                self.audioManager.resumeVOX()
                print("🔊 TTS finished - VOX resumed")
            }
        }
    }
    
    private func updateTranslationSetting() {
        // Çeviri ayarını güncelle
        // Sadece Türkçe VE Claude kapalıysa çevir
        if !isEnglish && !enableClaude {
            speechService.shouldTranslateToEnglish = true
            print("✅ Çeviri modu açık: Türkçe → İngilizce")
        } else {
            speechService.shouldTranslateToEnglish = false
            print("❌ Çeviri modu kapalı (Claude: \(enableClaude ? "açık" : "kapalı"))")
        }
    }
    
    private func toggleRecord() {
        if enableVOX {
            // VOX mode toggle
            if audioManager.isVOXActive {
                audioManager.stopVOXMode()
            } else {
                startVOXMode()
            }
        } else {
            // Normal mode toggle
            isRecording.toggle()
            
            if isRecording {
                recognizedText = ""
                responseText = ""
                startNormalRecording()
            } else {
                audioManager.stopRecording()
                speechService.stopRecording()
            }
        }
    }
    
    private func startVOXMode() {
        recognizedText = ""
        responseText = ""
        
        // Çeviri ayarını güncelle
        updateTranslationSetting()
        
        audioManager.startVOXMode()
    }
    
    private func handleVOXRecordingStarted() {
        let language = isEnglish ? "en-US" : "tr-TR"
        currentRecognitionLanguage = language
        speechService.startRecording(language: language)
        print("🎤 VOX: Speech recognition started")
    }
    
    private func handleVOXRecordingStopped() {
        speechService.stopRecording()
        print("🎤 VOX: Speech recognition stopped")
    }
    
    private func startNormalRecording() {
        let language = isEnglish ? "en-US" : "tr-TR"
        currentRecognitionLanguage = language
        
        // Çeviri ayarını güncelle
        updateTranslationSetting()
        
        audioManager.startRecording()
        speechService.startRecording(language: language)
    }
    
    private func toggleLanguage() {
        isEnglish.toggle()
        ttsService.setLanguage(isEnglish ? "en-US" : "tr-TR")
        
        // Dil değiştiğinde çeviri ayarını güncelle
        updateTranslationSetting()
    }
    
    private func handleRecognizedText(_ text: String, language: String) {
        guard !text.isEmpty else { return }
        
        if enableClaude {
            // Claude'a gönder
            claudeService.askClaude(question: text, maxWords: maxWords)
        } else {
            // Claude kapalı - sadece echo (tekrar seslendir)
            speakResponse(text, language: language)
        }
    }
    
    private func speakResponse(_ text: String, language: String?) {
        if let lang = language {
            print("🔊 Seslendirme dili: \(lang)")
            ttsService.setLanguage(lang)
            ttsService.speak(text: text)
            
            // Seslendirme bittikten sonra orijinal dile geri dön
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let originalLanguage = self.isEnglish ? "en-US" : "tr-TR"
                self.ttsService.setLanguage(originalLanguage)
            }
        } else {
            ttsService.speak(text: text)
        }
    }
    
    private func clearText() {
        recognizedText = ""
        responseText = ""
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black)
                
                Rectangle()
                    .fill(level > 0.25 ? Color.green : Color.red)
                    .frame(width: geometry.size.width * level)
                
                Text(String(format: "%.2f", level))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 5)
            }
            .cornerRadius(5)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioManager())
        .environmentObject(ClaudeService())
}
