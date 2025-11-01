//
//  ContentView.swift
//  AIAssistant
//
//  Main UI for voice assistant with Claude AI integration and VOX support
//

import SwiftUI
import Foundation  // ✅ For exit() function

// MARK: - Language Support
enum Language: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"
    case chinese = "zh"
    case spanish = "es"
    case russian = "ru"
    case arabic = "ar"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case portuguese = "pt"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .turkish: return "🇹🇷 Türkçe"
        case .english: return "🇺🇸 English"
        case .chinese: return "🇨🇳 中文"
        case .spanish: return "🇪🇸 Español"
        case .russian: return "🇷🇺 Русский"
        case .arabic: return "🇸🇦 العربية"
        case .french: return "🇫🇷 Français"
        case .german: return "🇩🇪 Deutsch"
        case .japanese: return "🇯🇵 日本語"
        case .portuguese: return "🇵🇹 Português"
        }
    }
    
    var shortName: String {
        switch self {
        case .turkish: return "TR"
        case .english: return "EN"
        case .chinese: return "ZH"
        case .spanish: return "ES"
        case .russian: return "RU"
        case .arabic: return "AR"
        case .french: return "FR"
        case .german: return "DE"
        case .japanese: return "JA"
        case .portuguese: return "PT"
        }
    }
    
    var speechCode: String {
        switch self {
        case .turkish: return "tr-TR"
        case .english: return "en-US"
        case .chinese: return "zh-CN"
        case .spanish: return "es-ES"
        case .russian: return "ru-RU"
        case .arabic: return "ar-SA"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .japanese: return "ja-JP"
        case .portuguese: return "pt-PT"
        }
    }
    
    var googleTranslateCode: String {
        return rawValue
    }
}

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var claudeService: ClaudeService
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var ttsService = TextToSpeechService()
    
    @State private var isRecording = false
    @State private var recognizedText = ""
    @State private var responseText = ""
    @State private var centerLanguage: Language = .turkish // ✅ Merkez dil (çeviri yapılacak ana dil)
    @State private var selectedLanguage: Language = .turkish // ✅ Konuşma dili
    @State private var micVolume: Double = 1.0
    @State private var speechVolume: Double = 1.0
    @State private var voxSensitivity: Double = 0.25 // ✅ Default 0.25 (25%)
    @State private var enableClaude = false
    @State private var enableVOX = false
    @State private var maxWords = 20
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentRecognitionLanguage: String = "tr-TR" // Tanıma yapılan dil
    
    var body: some View {
        NavigationView {
            ScrollView {  // ✅ ScrollView ekle - içerik sığmazsa scroll edilebilir
                VStack(spacing: 15) {  // ✅ spacing 20'den 15'e düşürüldü
                    // Header
                    headerView
                
                // Audio Level Indicator
                AudioLevelView(
                    level: audioManager.audioLevel,
                    voxSensitivity: voxSensitivity,
                    isVOXActive: audioManager.isVOXActive
                )
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
                .frame(maxHeight: 200)  // ✅ 300'den 200'e düşürüldü - daha fazla alan
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Controls
                controlsView
                
                // Volume Sliders
                slidersView
                
                // VOX Toggle
                voxToggleView
                
                // Center Language Selector
                centerLanguageView
                
                // Claude AI Toggle
                claudeToggleView
                
                // Mode Indicator
                modeIndicatorView
                
                // Action Buttons (Clear & Exit side by side)
                HStack(spacing: 15) {  // ✅ HStack - yan yana
                    // Clear Button
                    Button(action: clearText) {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    // Exit Button
                    Button(action: {
                        exit(0)
                    }) {
                        Label("Exit", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 20)  // ✅ Alt padding
            }
            .padding(.bottom, 20)  // ✅ ScrollView için ekstra padding
            }  // ✅ ScrollView kapanışı
            // ✅ Navigation title kaldırıldı
            .navigationBarHidden(true)  // ← Navigation bar'ı tamamen gizle
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
            
            // ✅ Dil seçici menü
            Menu {
                ForEach(Language.allCases) { language in
                    Button(action: {
                        selectedLanguage = language
                        handleLanguageChange()
                    }) {
                        HStack {
                            Text(language.displayName)
                            if selectedLanguage == language {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(languageButtonText)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(languageButtonColor)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    // ✅ Dil butonu metni - Claude ve merkez dil durumuna göre
    private var languageButtonText: String {
        if enableClaude {
            // Claude açık: Sadece konuşma dili
            return selectedLanguage.shortName
        } else {
            // Claude kapalı: Çeviri yönü
            if selectedLanguage == centerLanguage {
                // Konuşma dili = Merkez dil → Varsayılan hedefe çevir
                let defaultTarget = centerLanguage == .english ? Language.turkish : Language.english
                return "\(selectedLanguage.shortName)→\(defaultTarget.shortName)"
            } else {
                // Konuşma dili ≠ Merkez dil → Merkez dile çevir
                return "\(selectedLanguage.shortName)→\(centerLanguage.shortName)"
            }
        }
    }
    
    // ✅ Dil butonu rengi - Claude durumuna göre
    private var languageButtonColor: Color {
        if enableClaude {
            return Color.purple.opacity(0.2)
        } else {
            return selectedLanguage == centerLanguage ? Color.blue.opacity(0.2) : Color.green.opacity(0.2)
        }
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
        VStack(spacing: 10) {  // ✅ 15'ten 10'a düşürüldü
//            // Microphone Volume
//            VStack(alignment: .leading) {
//                Text("Microphone Volume: \(Int(micVolume * 100))%")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                
//                Slider(value: $micVolume, in: 0...1)
//                    .onChange(of: micVolume) { _, newValue in
//                        audioManager.setMicrophoneVolume(newValue)
//                    }
//            }
//            
//            // Speech Volume
//            VStack(alignment: .leading) {
//                Text("Speech Volume: \(Int(speechVolume * 100))%")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                
//                Slider(value: $speechVolume, in: 0...1)
//                    .onChange(of: speechVolume) { _, newValue in
//                        ttsService.setVolume(Float(newValue))
//                    }
//            }
            
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
        .padding(.vertical, 8)  // ✅ 10'dan 8'e düşürüldü
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    // ✅ Merkez Dil Seçici
    private var centerLanguageView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Center Language (Translation Hub):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    ForEach(Language.allCases) { language in
                        Button(action: {
                            centerLanguage = language
                            handleCenterLanguageChange()
                        }) {
                            HStack {
                                Text(language.displayName)
                                if centerLanguage == language {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(centerLanguage.displayName)
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            
            Text("All translations will go through this language")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var claudeToggleView: some View {
        VStack(spacing: 10) {
            Toggle("Enable Claude AI", isOn: $enableClaude)
                .padding(.horizontal)
                .onChange(of: enableClaude) { _, newValue in
                    // ✅ Claude toggle edildiğinde çeviri ayarını güncelle
                    updateTranslationSetting()
                    
                    // ✅ TTS dilini de güncelle (merkez dil mantığı)
                    if newValue {
                        // Claude açıldı: Orijinal dilde seslendir
                        ttsService.setLanguage(selectedLanguage.speechCode)
                    } else {
                        // Claude kapandı: Çevrilmiş dilde seslendir
                        if selectedLanguage == centerLanguage {
                            // Konuşma dili = Merkez dil → Varsayılan hedefe çevir
                            let defaultTarget = centerLanguage == .english ? Language.turkish : Language.english
                            ttsService.setLanguage(defaultTarget.speechCode)
                        } else {
                            // Konuşma dili ≠ Merkez dil → Merkez dile çevir
                            ttsService.setLanguage(centerLanguage.speechCode)
                        }
                    }
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
        .padding(.vertical, 8)  // ✅ 10'dan 8'e düşürüldü
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    // Mode Indicator View
    private var modeIndicatorView: some View {
        HStack {
            // Mode icon
            Image(systemName: enableClaude ? "brain.head.profile" : "arrow.left.arrow.right.circle")
                .font(.system(size: 20))
                .foregroundColor(.white)
            
            // Mode text
            Text(modeText)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(modeColor)
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var modeText: String {
        if enableClaude {
            // Claude açık: Sadece konuşma dili
            return selectedLanguage.shortName
        } else {
            // Claude kapalı: Çeviri yönü
            if selectedLanguage == centerLanguage {
                // Konuşma dili = Merkez dil → Varsayılan hedefe çevir
                let defaultTarget = centerLanguage == .english ? Language.turkish : Language.english
                return "\(selectedLanguage.shortName)→\(defaultTarget.shortName)"
            } else {
                // Konuşma dili ≠ Merkez dil → Merkez dile çevir
                return "\(selectedLanguage.shortName)→\(centerLanguage.shortName)"
            }
        }
    }
    
    private var modeColor: Color {
        if enableClaude {
            // Claude açık: Mor
            return Color.purple.opacity(0.8)
        } else {
            // Claude kapalı: Çeviri yönüne göre
            return selectedLanguage == centerLanguage ? Color.blue.opacity(0.8) : Color.green.opacity(0.8)
        }
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
        // ✅ CRITICAL: AudioManager referansını SpeechService'e bağla
        speechService.audioManager = audioManager
        
        // ✅ Başlangıç çeviri ayarını yap
        updateTranslationSetting()
        
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
            // ✅ Claude'ın yanıtını currentRecognitionLanguage'da seslendir
            // currentRecognitionLanguage zaten doğru dili tutuyor:
            // - Claude açık: Orijinal dil (çeviri yok)
            // - Claude kapalı: Çevrilmiş dil (echo için)
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
        // ✅ Claude açıkken çeviri YAPMA - orijinal dilde sor
        if enableClaude {
            speechService.shouldTranslateToTurkish = false
            speechService.shouldTranslateFromTurkish = false
            speechService.targetLanguage = nil
            speechService.sourceLanguage = nil
            print("❌ Claude aktif - çeviri kapalı (orijinal dilde iletişim)")
            return
        }
        
        // ✅ Claude kapalıyken: Echo için çeviri yap
        // Merkez dil mantığı: Konuşma dili ↔ Merkez dil
        if selectedLanguage == centerLanguage {
            // Konuşma dili = Merkez dil → Başka bir dile çevir (varsayılan)
            let defaultTarget = centerLanguage == .english ? Language.turkish : Language.english
            
            if centerLanguage == .turkish {
                speechService.shouldTranslateFromTurkish = true
                speechService.shouldTranslateToTurkish = false
                speechService.targetLanguage = defaultTarget.googleTranslateCode
                speechService.sourceLanguage = nil
            } else {
                speechService.shouldTranslateFromTurkish = false
                speechService.shouldTranslateToTurkish = false
                speechService.sourceLanguage = centerLanguage.googleTranslateCode
                speechService.targetLanguage = defaultTarget.googleTranslateCode
            }
            print("✅ Çeviri modu: \(selectedLanguage.shortName) → \(defaultTarget.shortName) (Echo)")
        } else {
            // Konuşma dili ≠ Merkez dil → Merkez dile çevir
            if centerLanguage == .turkish {
                // Merkez TR → TR'ye çevir
                speechService.shouldTranslateToTurkish = true
                speechService.shouldTranslateFromTurkish = false
                speechService.targetLanguage = nil
                speechService.sourceLanguage = nil
            } else if selectedLanguage == .turkish {
                // TR konuşuluyor, merkez başka dil → Merkez dile çevir
                speechService.shouldTranslateFromTurkish = true
                speechService.shouldTranslateToTurkish = false
                speechService.targetLanguage = centerLanguage.googleTranslateCode
                speechService.sourceLanguage = nil
            } else {
                // Başka dil → Merkez dile çevir (genel)
                speechService.shouldTranslateFromTurkish = false
                speechService.shouldTranslateToTurkish = false
                speechService.sourceLanguage = selectedLanguage.googleTranslateCode
                speechService.targetLanguage = centerLanguage.googleTranslateCode
            }
            print("✅ Çeviri modu: \(selectedLanguage.shortName) → \(centerLanguage.shortName) (Echo)")
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
        let language = selectedLanguage.speechCode
        currentRecognitionLanguage = language
        speechService.startRecording(language: language)
        print("🎤 VOX: Speech recognition started (\(selectedLanguage.shortName))")
    }
    
    private func handleVOXRecordingStopped() {
        speechService.stopRecording()
        print("🎤 VOX: Speech recognition stopped")
    }
    
    private func startNormalRecording() {
        let language = selectedLanguage.speechCode
        currentRecognitionLanguage = language
        
        // Çeviri ayarını güncelle
        updateTranslationSetting()
        
        audioManager.startRecording()
        speechService.startRecording(language: language)
    }
    
    private func handleLanguageChange() {
        // ✅ Claude açıkken: Orijinal dilde seslendir
        // ✅ Claude kapalıyken: Çevrilmiş dilde seslendir (merkez dil mantığı)
        if enableClaude {
            // Claude açık: Seçili dilde seslendir
            ttsService.setLanguage(selectedLanguage.speechCode)
        } else {
            // Claude kapalı: Çeviri hedef dilinde seslendir
            if selectedLanguage == centerLanguage {
                // Konuşma dili = Merkez dil → Varsayılan hedefe çevir
                let defaultTarget = centerLanguage == .english ? Language.turkish : Language.english
                ttsService.setLanguage(defaultTarget.speechCode)
            } else {
                // Konuşma dili ≠ Merkez dil → Merkez dile çevir
                ttsService.setLanguage(centerLanguage.speechCode)
            }
        }
        
        // Çeviri ayarını güncelle
        updateTranslationSetting()
    }
    
    private func handleCenterLanguageChange() {
        // Merkez dil değiştiğinde çeviri ayarlarını güncelle
        updateTranslationSetting()
        
        // TTS dilini de güncelle
        if !enableClaude {
            // Claude kapalıyken TTS dilini çeviri hedefine göre ayarla
            if selectedLanguage == centerLanguage {
                let defaultTarget = centerLanguage == .english ? Language.turkish : Language.english
                ttsService.setLanguage(defaultTarget.speechCode)
            } else {
                ttsService.setLanguage(centerLanguage.speechCode)
            }
        }
        
        print("🌍 Merkez dil değiştirildi: \(centerLanguage.displayName)")
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
            
            // ✅ Language is already set correctly, no need to restore
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
    let voxSensitivity: Double
    let isVOXActive: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.black)
                
                // Level bar
                Rectangle()
                    .fill(levelColor)
                    .frame(width: geometry.size.width * level)
                
                // ✅ VOX Threshold indicator (eğer VOX aktifse)
                if isVOXActive {
                    Rectangle()
                        .fill(Color.yellow.opacity(0.5))
                        .frame(width: 2)
                        .offset(x: geometry.size.width * calculatedThreshold)
                }
                
                // Level text
                HStack {
                    Text(String(format: "%.2f", level))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.yellow)
                    
                    if isVOXActive {
                        Text("| Threshold: \(String(format: "%.2f", calculatedThreshold))")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            }
            .cornerRadius(5)
        }
    }
    
    // ✅ Calculate actual VOX threshold (same formula as AudioManager)
    private var calculatedThreshold: Double {
        let minThreshold: Double = 0.15
        let maxThreshold: Double = 0.85
        return minThreshold + (voxSensitivity * (maxThreshold - minThreshold))
    }
    
    private var levelColor: Color {
        if isVOXActive {
            // VOX mode: show if above threshold
            return level >= calculatedThreshold ? Color.green : Color.red
        } else {
            // Normal mode: simple threshold at 0.25
            return level > 0.25 ? Color.green : Color.red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioManager())
        .environmentObject(ClaudeService())
}
