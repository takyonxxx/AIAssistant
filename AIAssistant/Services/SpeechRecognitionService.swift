//
//  SpeechRecognitionService.swift
//  AIAssistant
//
//  Speech-to-text using Apple's Speech framework and Google Cloud Speech API
//

import Foundation
import Speech
import AVFoundation

class SpeechRecognitionService: NSObject, ObservableObject {
    @Published var recognizedText = ""
    @Published var isRecognizing = false
    
    // ✅ Callback artık (text, language) alıyor
    var onRecognition: ((String, String) -> Void)?
    var onError: ((String) -> Void)?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // For Google API recording
    private var audioRecorder: AVAudioRecorder?
    private var currentLanguage: String = "tr-TR"
    private var currentRecordingURL: URL? // ✅ Store current recording URL
    
    // ✅ Recording timing
    private var recordingStartTime: Date?
    private let minimumRecordingDuration: TimeInterval = 0.5 // En az 0.5 saniye
    
    // Çeviri için
    var shouldTranslateFromTurkish: Bool = false  // TR → Başka dil
    var shouldTranslateToTurkish: Bool = false    // Başka dil → TR
    var targetLanguage: String? = nil             // Hedef dil
    var sourceLanguage: String? = nil             // Kaynak dil (genel çeviri için)
    
    // ✅ AudioManager referansı - tap çakışmasını önlemek için
    weak var audioManager: AudioManager?
    
    private var useGoogleAPI = false
    private let googleAPIKey = Constants.googleSpeechAPIKey
    
    override init() {
        super.init()
        requestSpeechAuthorization()
    }
    
    // MARK: - Authorization
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied:
                    self?.onError?("Konuşma tanıma erişimi reddedildi")
                case .restricted:
                    self?.onError?("Konuşma tanıma kısıtlı")
                case .notDetermined:
                    self?.onError?("Konuşma tanıma belirlenmedi")
                @unknown default:
                    break
                }
            }
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording(language: String) {
        currentLanguage = language
        recordingStartTime = Date()
        
        // Cancel any ongoing recognition
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        if audioRecorder?.isRecording == true {
            audioRecorder?.stop()
        }
        
        // ✅ FIX: VOX aktifse Google API kullan (tap çakışmasını önlemek için)
        let shouldUseGoogle = (audioManager?.isVOXActive == true) || useGoogleAPI
        
        if shouldUseGoogle {
            print("📱 Using Google API (VOX is active or manual selection)")
            startGoogleRecording()
        } else {
            print("🍎 Using Apple Speech Recognition")
            startAppleSpeechRecognition(language: language)
        }
    }
    
    func stopRecording() {
        // ✅ Check minimum recording duration
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            if duration < minimumRecordingDuration {
                print("⚠️ Recording too short (\(String(format: "%.2f", duration))s), ignoring...")
                
                // Cleanup
                if audioRecorder?.isRecording == true {
                    audioRecorder?.stop()
                }
                isRecognizing = false
                recordingStartTime = nil
                
                // Delete the short recording
                if let url = currentRecordingURL {
                    try? FileManager.default.removeItem(at: url)
                }
                currentRecordingURL = nil
                
                return
            }
        }
        
        // ✅ VOX aktifse Google kullanıyoruz
        let shouldUseGoogle = (audioManager?.isVOXActive == true) || useGoogleAPI
        
        if shouldUseGoogle {
            stopGoogleRecording()
        } else {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            isRecognizing = false
        }
        
        recordingStartTime = nil
    }
    
    // MARK: - Apple Speech Recognition
    
    private func startAppleSpeechRecognition(language: String) {
        let languageCode = language == "tr-TR" ? "tr-TR" : "en-US"
        let locale = Locale(identifier: languageCode)
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            onError?("Konuşma tanıma kullanılamıyor")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            onError?("Tanıma isteği oluşturulamadı")
            return
        }
        
        let inputNode = audioEngine.inputNode
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                let transcribedText = result.bestTranscription.formattedString
                self.recognizedText = transcribedText
                isFinal = result.isFinal
                
                if isFinal {
                    print("Tanınan metin: \(transcribedText)")
                    
                    // Çeviri kontrolü
                    if self.shouldTranslateFromTurkish && self.currentLanguage == "tr-TR" {
                        // TR → Hedef dile çevir
                        let targetLang = self.targetLanguage ?? "en"
                        self.translateFromTurkish(turkishText: transcribedText, targetLanguage: targetLang)
                    } else if self.shouldTranslateToTurkish && self.currentLanguage != "tr-TR" {
                        // Başka dil → TR'ye çevir
                        self.translateToTurkish(sourceText: transcribedText, sourceLanguage: self.extractLanguageCode(from: self.currentLanguage))
                    } else if let srcLang = self.sourceLanguage, let tgtLang = self.targetLanguage {
                        // Genel çeviri: X → Y
                        self.translateGeneral(sourceText: transcribedText, sourceLanguage: srcLang, targetLanguage: tgtLang)
                    } else {
                        // Çeviri yok
                        self.onRecognition?(transcribedText, self.currentLanguage)
                    }
                }
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isRecognizing = false
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecognizing = true
            print("Apple konuşma tanıma başlatıldı - Dil: \(languageCode)")
        } catch {
            onError?("Ses motoru başlatılamadı: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Translation
    
    // TR → Herhangi bir dil
    private func translateFromTurkish(turkishText: String, targetLanguage: String) {
        let urlString = "https://translation.googleapis.com/language/translate/v2?key=\(googleAPIKey)"
        
        guard let url = URL(string: urlString) else {
            onError?("Çeviri URL'si geçersiz")
            return
        }
        
        let requestBody: [String: Any] = [
            "q": turkishText,
            "source": "tr",
            "target": targetLanguage,
            "format": "text"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            onError?("Çeviri isteği oluşturulamadı")
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri hatası: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self?.onError?("Geçersiz yanıt")
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Google Translate Error Response: \(errorString)")
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri hatası (\(httpResponse.statusCode))")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri sunucu hatası: \(httpResponse.statusCode)")
                    }
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri verisi alınamadı")
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let translations = dataObj["translations"] as? [[String: Any]],
                   let translatedText = translations.first?["translatedText"] as? String {
                    
                    DispatchQueue.main.async {
                        print("✅ Çeviri: '\(turkishText)' → '\(translatedText)' (\(targetLanguage.uppercased()))")
                        
                        // Çevrilmiş metin + hedef dil kodu gönder
                        let speechCode = self?.languageCodeToSpeechCode(targetLanguage) ?? "en-US"
                        self?.onRecognition?(translatedText, speechCode)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri yanıtı ayrıştırılamadı")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri JSON hatası: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // Herhangi bir dil → TR
    private func translateToTurkish(sourceText: String, sourceLanguage: String) {
        let urlString = "https://translation.googleapis.com/language/translate/v2?key=\(googleAPIKey)"
        
        guard let url = URL(string: urlString) else {
            onError?("Çeviri URL'si geçersiz")
            return
        }
        
        let requestBody: [String: Any] = [
            "q": sourceText,
            "source": sourceLanguage,
            "target": "tr",
            "format": "text"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            onError?("Çeviri isteği oluşturulamadı")
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri hatası: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self?.onError?("Geçersiz yanıt")
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Google Translate Error Response: \(errorString)")
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri hatası (\(httpResponse.statusCode))")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri sunucu hatası: \(httpResponse.statusCode)")
                    }
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri verisi alınamadı")
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let translations = dataObj["translations"] as? [[String: Any]],
                   let translatedText = translations.first?["translatedText"] as? String {
                    
                    DispatchQueue.main.async {
                        print("✅ Çeviri: '\(sourceText)' → '\(translatedText)' (\(sourceLanguage.uppercased())→TR)")
                        
                        // Türkçe metin + Türkçe dil kodu gönder
                        self?.onRecognition?(translatedText, "tr-TR")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri yanıtı ayrıştırılamadı")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri JSON hatası: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // Genel çeviri: Herhangi bir dil → Herhangi bir dil
    private func translateGeneral(sourceText: String, sourceLanguage: String, targetLanguage: String) {
        let urlString = "https://translation.googleapis.com/language/translate/v2?key=\(googleAPIKey)"
        
        guard let url = URL(string: urlString) else {
            onError?("Çeviri URL'si geçersiz")
            return
        }
        
        let requestBody: [String: Any] = [
            "q": sourceText,
            "source": sourceLanguage,
            "target": targetLanguage,
            "format": "text"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            onError?("Çeviri isteği oluşturulamadı")
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri hatası: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self?.onError?("Geçersiz yanıt")
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Google Translate Error Response: \(errorString)")
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri hatası (\(httpResponse.statusCode))")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri sunucu hatası: \(httpResponse.statusCode)")
                    }
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri verisi alınamadı")
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let translations = dataObj["translations"] as? [[String: Any]],
                   let translatedText = translations.first?["translatedText"] as? String {
                    
                    DispatchQueue.main.async {
                        print("✅ Çeviri: '\(sourceText)' → '\(translatedText)' (\(sourceLanguage.uppercased())→\(targetLanguage.uppercased()))")
                        
                        // Çevrilmiş metin + hedef dil kodu gönder
                        let speechCode = self?.languageCodeToSpeechCode(targetLanguage) ?? "en-US"
                        self?.onRecognition?(translatedText, speechCode)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onError?("Çeviri yanıtı ayrıştırılamadı")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.onError?("Çeviri JSON hatası: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // MARK: - Google Cloud Speech API Recording
    
    private func startGoogleRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            
            // ✅ Generate and store recording URL
            currentRecordingURL = generateRecordingURL()
            
            guard let recordingURL = currentRecordingURL else {
                onError?("Kayıt URL'si oluşturulamadı")
                return
            }
            
            // ✅ Delete old recording if exists
            if FileManager.default.fileExists(atPath: recordingURL.path) {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecognizing = true
            print("📝 Google API kaydı başlatıldı: \(recordingURL.lastPathComponent)")
            
        } catch {
            onError?("Ses kaydı başlatılamadı: \(error.localizedDescription)")
        }
    }
    
    private func stopGoogleRecording() {
        audioRecorder?.stop()
        isRecognizing = false
        
        // ✅ Wait a bit longer for file to be written
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.sendAudioToGoogle()
            
            // ✅ Cleanup after sending
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let url = self?.currentRecordingURL {
                    try? FileManager.default.removeItem(at: url)
                    print("🗑️ Cleaned up recording file")
                }
                self?.currentRecordingURL = nil
            }
        }
    }
    
    // MARK: - Google Cloud Speech API
    
    private func sendAudioToGoogle() {
        // ✅ Use stored recording URL
        guard let audioURL = currentRecordingURL else {
            print("❌ No recording URL stored")
            onError?("Kayıt dosyası bulunamadı")
            return
        }
        
        // ✅ Check if file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ Audio file does not exist: \(audioURL.path)")
            onError?("Ses dosyası bulunamadı")
            return
        }
        
        do {
            let audioData = try Data(contentsOf: audioURL)
            
            // ✅ Check file size
            let fileSizeKB = Double(audioData.count) / 1024.0
            print("📦 Audio file size: \(String(format: "%.2f", fileSizeKB)) KB")
            
            if audioData.count < 100 {
                print("❌ Audio file too small (\(audioData.count) bytes), likely empty")
                onError?("Ses kaydı çok kısa veya boş")
                return
            }
            
            let base64Audio = audioData.base64EncodedString()
            
            let languageCode = currentLanguage == "tr-TR" ? "tr-TR" : "en-US"
            
            let requestBody: [String: Any] = [
                "config": [
                    "encoding": "LINEAR16",
                    "sampleRateHertz": 16000,
                    "languageCode": languageCode,
                    "enableAutomaticPunctuation": true
                ],
                "audio": [
                    "content": base64Audio
                ]
            ]
            
            guard let url = URL(string: "\(Constants.googleSpeechAPIURL)?key=\(googleAPIKey)") else {
                onError?("Geçersiz API URL")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            print("🚀 Sending audio to Google API...")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.onError?("Ağ hatası: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    DispatchQueue.main.async {
                        self.onError?("Geçersiz yanıt")
                    }
                    return
                }
                
                print("📨 Google API Response Code: \(httpResponse.statusCode)")
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("❌ Google Speech API Error (\(httpResponse.statusCode)): \(errorString)")
                    }
                    DispatchQueue.main.async {
                        self.onError?("Sunucu hatası: \(httpResponse.statusCode)")
                    }
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        self.onError?("Veri alınamadı")
                    }
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let firstResult = results.first,
                       let alternatives = firstResult["alternatives"] as? [[String: Any]],
                       let transcript = alternatives.first?["transcript"] as? String {
                        
                        DispatchQueue.main.async {
                            self.recognizedText = transcript
                            print("✅ Tanınan metin: \(transcript)")
                            
                            // Çeviri kontrolü
                            if self.shouldTranslateFromTurkish && self.currentLanguage == "tr-TR" {
                                // TR → Hedef dile çevir
                                let targetLang = self.targetLanguage ?? "en"
                                self.translateFromTurkish(turkishText: transcript, targetLanguage: targetLang)
                            } else if self.shouldTranslateToTurkish && self.currentLanguage != "tr-TR" {
                                // Başka dil → TR'ye çevir
                                self.translateToTurkish(sourceText: transcript, sourceLanguage: self.extractLanguageCode(from: self.currentLanguage))
                            } else if let srcLang = self.sourceLanguage, let tgtLang = self.targetLanguage {
                                // Genel çeviri: X → Y
                                self.translateGeneral(sourceText: transcript, sourceLanguage: srcLang, targetLanguage: tgtLang)
                            } else {
                                // Çeviri yok
                                self.onRecognition?(transcript, self.currentLanguage)
                            }
                        }
                    } else {
                        print("⚠️ No transcription in response")
                        DispatchQueue.main.async {
                            self.onError?("Ses tanınamadı (çok sessiz veya anlaşılmaz)")
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onError?("JSON ayrıştırma hatası: \(error.localizedDescription)")
                    }
                }
            }.resume()
            
        } catch {
            onError?("Ses dosyası okunamadı: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    // Speech code'dan (zh-CN) dil koduna (zh) dönüştürme
    private func extractLanguageCode(from speechCode: String) -> String {
        return String(speechCode.prefix(2))
    }
    
    // Dil kodundan (zh) speech code'a (zh-CN) dönüştürme
    private func languageCodeToSpeechCode(_ code: String) -> String {
        switch code.lowercased() {
        case "en": return "en-US"
        case "zh": return "zh-CN"
        case "es": return "es-ES"
        case "ru": return "ru-RU"
        case "ar": return "ar-SA"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "ja": return "ja-JP"
        case "pt": return "pt-PT"
        case "it": return "it-IT"
        case "tr": return "tr-TR"
        default: return "en-US"
        }
    }
    
    private func generateRecordingURL() -> URL? {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // ✅ Use timestamp to avoid conflicts
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return documentDirectory.appendingPathComponent("google_recording_\(timestamp).wav")
    }
    
    func stopSpeaking() {
        // Bu fonksiyon artık kullanılmıyor ama uyumluluk için bırakıldı
    }
    
    deinit {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
        }
        audioRecorder?.stop()
    }
}
