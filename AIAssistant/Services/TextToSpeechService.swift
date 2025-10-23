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
    
    // Callbacks
    var onSpeechStarted: (() -> Void)?
    var onSpeechFinished: (() -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Speech Control
    
    func speak(text: String) {
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
        onSpeechFinished?()
    }
    
    func setLanguage(_ languageCode: String) {
        currentLanguage = languageCode
    }
    
    func setVolume(_ newVolume: Float) {
        volume = newVolume
    }
    
    // MARK: - Apple TTS
    
    private func speakWithAppleTTS(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = volume
        
        isSpeaking = true
        onSpeechStarted?()
        synthesizer.speak(utterance)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        onSpeechStarted?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        onSpeechFinished?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        onSpeechFinished?()
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
            print("Invalid Google TTS URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Failed to encode request: \(error)")
            return
        }
        
        isSpeaking = true
        onSpeechStarted?()
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Google TTS error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.onSpeechFinished?()
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.onSpeechFinished?()
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
                    DispatchQueue.main.async {
                        self.isSpeaking = false
                        self.onSpeechFinished?()
                    }
                }
            } catch {
                print("Failed to process Google TTS response: \(error)")
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.onSpeechFinished?()
                }
            }
        }.resume()
    }
    
    private func playAudioFile(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = volume
            audioPlayer?.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 0)) { [weak self] in
                self?.isSpeaking = false
                self?.onSpeechFinished?()
            }
        } catch {
            print("Failed to play audio: \(error)")
            isSpeaking = false
            onSpeechFinished?()
        }
    }
}
