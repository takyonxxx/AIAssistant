
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
    
    // Çeviri için
    var shouldTranslateToEnglish: Bool = false
    
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
        
        // Cancel any ongoing recognition
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        if audioRecorder?.isRecording == true {
            audioRecorder?.stop()
        }
        
        if useGoogleAPI {
            startGoogleRecording()
        } else {
            startAppleSpeechRecognition(language: language)
        }
    }
    
    func stopRecording() {
        if useGoogleAPI {
            stopGoogleRecording()
        } else {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            isRecognizing = false
        }
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
                    
                    // Eğer Türkçe ve çeviri gerekiyorsa
                    if self.currentLanguage == "tr-TR" && self.shouldTranslateToEnglish {
                        // Türkçe tanındı → İngilizce'ye çevir
                        self.translateAndSpeak(turkishText: transcribedText)
                    } else {
                        // Çeviri yok, dil kodunu da gönder
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
    
    private func translateAndSpeak(turkishText: String) {
        let urlString = "https://translation.googleapis.com/language/translate/v2?key=\(googleAPIKey)"
        
        guard let url = URL(string: urlString) else {
            onError?("Çeviri URL'si geçersiz")
            return
        }
        
        let requestBody: [String: Any] = [
            "q": turkishText,
            "source": "tr",
            "target": "en",
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
                        print("✅ Çeviri: '\(turkishText)' → '\(translatedText)'")
                        
                        // İngilizce metin + İngilizce dil kodu gönder
                        self?.onRecognition?(translatedText, "en-US")
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
            
            guard let recordingURL = getRecordingURL() else {
                onError?("Kayıt URL'si oluşturulamadı")
                return
            }
            
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecognizing = true
            print("Google API kaydı başlatıldı")
            
        } catch {
            onError?("Ses kaydı başlatılamadı: \(error.localizedDescription)")
        }
    }
    
    private func stopGoogleRecording() {
        audioRecorder?.stop()
        isRecognizing = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendAudioToGoogle()
        }
    }
    
    // MARK: - Google Cloud Speech API
    
    private func sendAudioToGoogle() {
        guard let audioURL = getRecordingURL() else {
            onError?("Kayıt dosyası bulunamadı")
            return
        }
        
        do {
            let audioData = try Data(contentsOf: audioURL)
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
                
                guard (200...299).contains(httpResponse.statusCode) else {
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
                            print("Tanınan metin: \(transcript)")
                            
                            // Eğer Türkçe ve çeviri gerekiyorsa
                            if self.currentLanguage == "tr-TR" && self.shouldTranslateToEnglish {
                                // Türkçe tanındı → İngilizce'ye çevir
                                self.translateAndSpeak(turkishText: transcript)
                            } else {
                                // Çeviri yok, dil kodunu da gönder
                                self.onRecognition?(transcript, self.currentLanguage)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.onError?("Yanıt ayrıştırılamadı")
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
    
    private func getRecordingURL() -> URL? {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentDirectory.appendingPathComponent("recording.wav")
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
