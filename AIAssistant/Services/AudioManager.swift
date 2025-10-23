//
//  AudioManager.swift
//  AIAssistant
//
//  Manages audio recording and monitoring with VOX support
//

import Foundation
import AVFoundation
import Combine

class AudioManager: NSObject, ObservableObject {
    @Published var audioLevel: Double = 0.0
    @Published var isRecording = false
    @Published var isVOXActive = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var levelTimer: Timer?
    
    // ✅ VOX Sensitivity ayarları
    var voxSensitivity: Double = 0.25 {
        didSet {
            print("🎚️ VOX Sensitivity: \(Int(voxSensitivity * 100))%")
        }
    }
    private var microphoneVolume: Double = 1.0
    
    // VOX settings
    var isVOXEnabled = false
    private var silenceDuration: TimeInterval = 0
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 saniye sessizlik
    private var isVOXRecording = false
    private var isVOXPaused = false // TTS çalışırken pause
    
    // Callbacks
    var onVOXRecordingStarted: (() -> Void)?
    var onVOXRecordingStopped: (() -> Void)?
    
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try audioSession.setActive(true)
            
            AVAudioApplication.requestRecordPermission { granted in
                if !granted {
                    print("Microphone permission denied")
                }
            }
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - VOX Mode
    
    func startVOXMode() {
        guard !isVOXActive else { return }
        
        isVOXActive = true
        isVOXRecording = false
        isVOXPaused = false
        silenceDuration = 0
        
        startMonitoringAudioLevel()
        
        print("🎤 VOX mode started - Listening...")
    }
    
    func stopVOXMode() {
        guard isVOXActive else { return }
        
        isVOXActive = false
        
        if isVOXRecording {
            stopRecording()
            isVOXRecording = false
        }
        
        stopMonitoringAudioLevel()
        
        print("🎤 VOX mode stopped")
    }
    
    // TTS çalışırken VOX'u pause et
    func pauseVOX() {
        guard isVOXActive else { return }
        
        isVOXPaused = true
        
        // Eğer kayıt varsa durdur
        if isVOXRecording {
            stopRecording()
            isVOXRecording = false
        }
        
        // ✅ CRITICAL: Stop audio engine to free audio resources for TTS
        if let audioEngine = audioEngine, audioEngine.isRunning {
            inputNode?.removeTap(onBus: 0)
            audioEngine.stop()
            print("🎧 VOX audio engine stopped for TTS")
        }
        
        print("⏸️ VOX paused (TTS speaking)")
    }
    
    // TTS bitince VOX'u devam ettir
    func resumeVOX() {
        guard isVOXActive else { return }
        
        isVOXPaused = false
        silenceDuration = 0
        
        // ✅ CRITICAL: Restart audio engine for VOX monitoring
        setupAudioEngineForVOX()
        
        print("▶️ VOX resumed (TTS finished)")
    }
    
    // MARK: - Tap Management for Speech Recognition
    
    func pauseTapForSpeechRecognition() {
        guard let inputNode = inputNode, let audioEngine = audioEngine, audioEngine.isRunning else { return }
        
        // Tap'i kaldır ama engine'i çalışır durumda bırak
        inputNode.removeTap(onBus: 0)
        print("🎧 VOX tap paused for speech recognition")
    }
    
    func resumeTapAfterSpeechRecognition() {
        guard let inputNode = inputNode, let audioEngine = audioEngine, audioEngine.isRunning else {
            // Engine durmuşsa yeniden başlat
            if isVOXActive {
                setupAudioEngineForVOX()
            }
            return
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        print("🎧 VOX tap resumed after speech recognition")
    }
    
    // MARK: - Recording Controls
    
    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.wav")
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: recordingSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            
            if !isVOXActive {
                startMonitoringAudioLevel()
            }
            
            print("Recording started")
        } catch {
            print("Could not start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        if !isVOXActive {
            stopMonitoringAudioLevel()
        }
        
        print("Recording stopped")
    }
    
    func getRecordingURL() -> URL? {
        return getDocumentsDirectory().appendingPathComponent("recording.wav")
    }
    
    // MARK: - Audio Level Monitoring
    
    private func startMonitoringAudioLevel() {
        if !isVOXActive {
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }
        } else {
            setupAudioEngineForVOX()
        }
    }
    
    private func setupAudioEngineForVOX() {
        // ✅ Stop existing engine if running
        if let existingEngine = audioEngine, existingEngine.isRunning {
            inputNode?.removeTap(onBus: 0)
            existingEngine.stop()
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            print("🎧 Audio engine started for VOX monitoring")
        } catch {
            print("❌ Could not start audio engine: \(error.localizedDescription)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frames = buffer.frameLength
        var sum: Float = 0.0
        var peak: Float = 0.0
        
        // Calculate RMS and Peak
        for i in 0..<Int(frames) {
            let sample = abs(channelData[i])
            sum += sample * sample
            peak = max(peak, sample)
        }
        
        let rms = sqrt(sum / Float(frames))
        
        // Daha iyi normalize etme - RMS ve Peak karışımı
        let normalizedRMS = min(Double(rms) * 50.0, 1.0) // RMS'i amplify et
        let normalizedPeak = min(Double(peak) * 2.0, 1.0) // Peak'i de kullan
        
        // İkisinin ortalamasını al
        let finalLevel = (normalizedRMS + normalizedPeak) / 2.0
        let adjustedLevel = min(finalLevel * microphoneVolume, 1.0)
        
        DispatchQueue.main.async {
            self.audioLevel = adjustedLevel
            self.checkVOXThreshold(level: adjustedLevel)
        }
    }
    
    private func checkVOXThreshold(level: Double) {
        guard isVOXActive && !isVOXPaused else { return }
        
        // ✅ FIX: Threshold hesaplama - daha yüksek eşik değeri
        // voxSensitivity: 0.0-1.0 arası (kullanıcı ayarı)
        // Minimum: 0.15, Maximum: 0.85
        let minThreshold: Double = 0.15
        let maxThreshold: Double = 0.85
        let actualThreshold = minThreshold + (voxSensitivity * (maxThreshold - minThreshold))
        
        // %25 sensitivity = 0.15 + (0.25 * 0.70) = 0.325 threshold
        // %50 sensitivity = 0.15 + (0.50 * 0.70) = 0.50 threshold
        // %100 sensitivity = 0.15 + (1.0 * 0.70) = 0.85 threshold
        
        if level >= actualThreshold {
            // Ses eşiği geçildi
            silenceDuration = 0
            
            if !isVOXRecording {
                // Kayıt başlat
                isVOXRecording = true
                startRecording()
                onVOXRecordingStarted?()
                print("🔴 VOX: Recording started (level: \(String(format: "%.3f", level)), threshold: \(String(format: "%.3f", actualThreshold)))")
            }
        } else if isVOXRecording {
            // Sessizlik başladı
            silenceDuration += 0.05
            
            if silenceDuration >= silenceThreshold {
                // Yeterince sessizlik oldu, kaydı durdur
                isVOXRecording = false
                stopRecording()
                onVOXRecordingStopped?()
                silenceDuration = 0
                print("⏸️ VOX: Recording stopped (silence detected)")
            }
        }
    }
    
    private func stopMonitoringAudioLevel() {
        levelTimer?.invalidate()
        levelTimer = nil
        
        if let audioEngine = audioEngine, audioEngine.isRunning {
            inputNode?.removeTap(onBus: 0)
            audioEngine.stop()
            print("🎧 Audio engine stopped")
        }
        
        audioLevel = 0.0
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0.0
            return
        }
        
        recorder.updateMeters()
        
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalizedLevel = pow(10.0, averagePower / 20.0)
        let adjustedLevel = min(normalizedLevel * Float(microphoneVolume), 1.0)
        
        DispatchQueue.main.async {
            self.audioLevel = Double(adjustedLevel)
        }
    }
    
    // MARK: - Volume Control
    
    func setMicrophoneVolume(_ volume: Double) {
        microphoneVolume = volume
    }
    
    // MARK: - Helpers
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    deinit {
        stopVOXMode()
        stopRecording()
    }
}
