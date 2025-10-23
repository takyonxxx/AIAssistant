//
//  TextToSpeechService.swift
//  AIAssistant
//
//  Text-to-speech using AVSpeechSynthesizer and Google Cloud TTS
//

import Foundation
import AVFoundation

class TextToSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentLanguage = "en-US"
    private var volume: Float = 1.0
    
    private var useGoogleTTS = false
    private var audioPlayer: AVAudioPlayer?
    
    // ✅ Prevent duplicate callbacks
    private var hasNotifiedStart = false
    private var hasNotifiedFinish = false
    
    // Callbacks
    var onSpeechStarted: (() -> Void)?
    var onSpeechFinished: (() -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Speech Control
    
    func speak(text: String) {
        guard !text.isEmpty else {
            print("⚠️ Empty text, skipping TTS")
            return
        }
        
        // ✅ Reset callback flags
        hasNotifiedStart = false
        hasNotifiedFinish = false
        
        // ✅ Stop any ongoing speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
        }
        
        print("🔊 TTS Request: '\(text)' (lang: \(currentLanguage), vol: \(Int(volume * 100))%)")
        
        if useGoogleTTS {
            speakWithGoogleTTS(text: text)
        } else {
            speakWithAppleTTS(text: text)
        }
    }
    
    func stop() {
        if useGoogleTTS {
            audioPlayer?.stop()
        } else {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        
        // ✅ Restore default audio session
        restoreDefaultAudioSession()
        
        // ✅ Notify finish only once
        if !hasNotifiedFinish {
            hasNotifiedFinish = true
            onSpeechFinished?()
        }
        
        print("⏹️ TTS stopped")
    }
    
    func setLanguage(_ languageCode: String) {
        currentLanguage = languageCode
        print("🌐 TTS language: \(languageCode)")
    }
    
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        print("🔊 TTS volume: \(Int(volume * 100))%")
    }
    
    // MARK: - Apple TTS
    
    private func speakWithAppleTTS(text: String) {
        // ✅ Configure audio session for better TTS playback (without changing category)
        configureAudioSessionForTTS()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLanguage)
        utterance.rate = 0.5 // Normal speed
        utterance.pitchMultiplier = 1.0
        utterance.volume = volume
        
        // ✅ Force output to speaker
        utterance.prefersAssistiveTechnologySettings = false
        
        isSpeaking = true
        synthesizer.speak(utterance)
        
        print("🎤 TTS: Utterance queued for playback")
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            
            // ✅ Notify start only once
            if !self.hasNotifiedStart {
                self.hasNotifiedStart = true
                self.onSpeechStarted?()
                print("▶️ TTS: Speech started")
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // ✅ Debug: This confirms audio is actually playing
        if characterRange.location == 0 {
            print("🎵 TTS: Actually playing audio...")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            
            // ✅ Wait a bit before restoring audio session to ensure audio output completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // ✅ Restore default audio session
                self.restoreDefaultAudioSession()
                
                // ✅ Notify finish only once
                if !self.hasNotifiedFinish {
                    self.hasNotifiedFinish = true
                    self.onSpeechFinished?()
                    print("⏸️ TTS: Speech finished")
                }
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            
            // ✅ Wait a bit before restoring audio session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // ✅ Restore default audio session
                self.restoreDefaultAudioSession()
                
                // ✅ Notify finish only once
                if !self.hasNotifiedFinish {
                    self.hasNotifiedFinish = true
                    self.onSpeechFinished?()
                    print("⏹️ TTS: Speech cancelled")
                }
            }
        }
    }
    
    // MARK: - Google Cloud TTS
    
    private func speakWithGoogleTTS(text: String) {
        let requestBody: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": currentLanguage,
                "name": currentLanguage == "en-US" ? "en-US-Neural2-F" : "tr-TR-Standard-A"
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "pitch": 0.0,
                "speakingRate": 1.0
            ]
        ]
        
        guard let url = URL(string: Constants.googleTTSAPIURL) else {
            print("❌ Invalid Google TTS URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("❌ Failed to encode request: \(error)")
            return
        }
        
        // ✅ DON'T change audio session - keep current .playAndRecord mode
        
        isSpeaking = true
        
        // ✅ Notify start only once
        if !hasNotifiedStart {
            hasNotifiedStart = true
            onSpeechStarted?()
            print("▶️ TTS: Google TTS started")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Google TTS error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.handleSpeechFinished()
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.handleSpeechFinished()
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Google TTS Error (\(httpResponse.statusCode)): \(errorString)")
                }
                DispatchQueue.main.async {
                    self.handleSpeechFinished()
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.handleSpeechFinished()
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let audioContent = json["audioContent"] as? String,
                   let audioData = Data(base64Encoded: audioContent) {
                    
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_audio.mp3")
                    try audioData.write(to: tempURL)
                    
                    DispatchQueue.main.async {
                        self.playAudioFile(url: tempURL)
                    }
                } else {
                    print("⚠️ No audio content in response")
                    DispatchQueue.main.async {
                        self.handleSpeechFinished()
                    }
                }
            } catch {
                print("❌ Failed to process Google TTS response: \(error)")
                DispatchQueue.main.async {
                    self.handleSpeechFinished()
                }
            }
        }.resume()
    }
    
    private func playAudioFile(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = volume
            audioPlayer?.play()
            
            // ✅ Schedule finish notification after audio duration
            let duration = audioPlayer?.duration ?? 0
            print("🎵 Playing audio file (duration: \(String(format: "%.2f", duration))s)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
                self?.handleSpeechFinished()
            }
        } catch {
            print("❌ Failed to play audio: \(error)")
            handleSpeechFinished()
        }
    }
    
    // MARK: - Helper
    
    private func configureAudioSessionForTTS() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // ✅ Keep .playAndRecord but optimize for speech
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio, // ✅ Better for TTS
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers] // ✅ Duck other audio
            )
            
            // ✅ Force output to speaker
            try audioSession.overrideOutputAudioPort(.speaker)
            
            print("✅ Audio session optimized for TTS (speaker output)")
        } catch {
            print("❌ Failed to configure audio session for TTS: \(error.localizedDescription)")
        }
    }
    
    private func handleSpeechFinished() {
        isSpeaking = false
        
        // ✅ Wait a bit before restoring audio session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // ✅ Restore default settings
            self.restoreDefaultAudioSession()
            
            // ✅ Notify finish only once
            if !self.hasNotifiedFinish {
                self.hasNotifiedFinish = true
                self.onSpeechFinished?()
                print("⏸️ TTS: Speech finished")
            }
        }
    }
    
    private func restoreDefaultAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // ✅ Restore to default .playAndRecord
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            
            print("✅ Audio session restored to default")
        } catch {
            print("❌ Failed to restore audio session: \(error.localizedDescription)")
        }
    }
    
    deinit {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
    }
}
