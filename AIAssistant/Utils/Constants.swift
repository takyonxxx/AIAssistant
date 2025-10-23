//
//  Constants.swift
//  AIAssistant
//
//  API keys and configuration constants
//
//  IMPORTANT: Replace these with your actual API keys
//  Do not commit this file with real API keys to version control
//

import Foundation

struct Constants {
    // Google Speech-to-Text API
    static let googleSpeechAPIURL = "https://speech.googleapis.com/v1/speech:recognize?key=\(googleSpeechAPIKey)"
    static let googleSpeechAPIKey = "YOUR_GOOGLE_SPEECH_API_KEY"
    
    // Google Text-to-Speech API
    static let googleTTSAPIURL = "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(googleTTSAPIKey)"
    static let googleTTSAPIKey = "YOUR_GOOGLE_TTS_API_KEY"
    
    // Translation API (MyMemory via RapidAPI)
    static let translateURL = "https://translated-mymemory---translation-memory.p.rapidapi.com/get"
    static let translateHost = "translated-mymemory---translation-memory.p.rapidapi.com"
    static let translateAPIKey = "YOUR_RAPIDAPI_KEY"
    
    // Claude (Anthropic) API
    // Get your API key from: https://console.anthropic.com/settings/keys
    static let claudeAPIKey = "YOUR_CLAUDE_API_KEY"
    
    // Audio Settings
    static let sampleRate: Double = 16000.0
    static let channelCount: Int = 1
    static let recordingFormat = "wav"
    
    // VOX Settings
    static let silenceTimeoutMS = 2500
    static let speechCooldownMS = 1500
    static let voxDebounceMS = 500
    static let minRecordDuration = 1500
    static let maxRecordDuration = 30000
}
