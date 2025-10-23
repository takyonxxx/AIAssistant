# AI Assistant - iOS App
Voice assistant with Claude AI integration, speech recognition, text-to-speech and translation.

## Setup

1. Open `AIAssistant.xcodeproj` in Xcode 16.1+

2. Edit `AIAssistant/Utils/Constants.swift` - add your API keys:

   ```swift
   // Google Speech-to-Text API
   static let googleSpeechAPIKey = "YOUR_GOOGLE_SPEECH_API_KEY"
   
   // Google Text-to-Speech API
   static let googleTTSAPIKey = "YOUR_GOOGLE_TTS_API_KEY"
   
   // RapidAPI (Translation)
   static let translateAPIKey = "YOUR_RAPIDAPI_KEY"
   
   // Claude (Anthropic) API
   static let claudeAPIKey = "YOUR_CLAUDE_API_KEY"
   ```

3. Select your team in Signing & Capabilities

4. Press Cmd+R to run

## API Keys

You need to get API keys from these services:

### 1. Google Speech-to-Text API
- **Purpose:** Voice recognition
- **Get key:** https://console.cloud.google.com/apis/credentials
- **Setup:**
  1. Create a Google Cloud project
  2. Enable Speech-to-Text API
  3. Create API key
  4. Add to `googleSpeechAPIKey`

### 2. Google Text-to-Speech API
- **Purpose:** Voice output
- **Get key:** https://console.cloud.google.com/apis/credentials
- **Setup:**
  1. Enable Text-to-Speech API (same project)
  2. Use same API key or create new one
  3. Add to `googleTTSAPIKey`

### 3. RapidAPI (MyMemory Translation)
- **Purpose:** Text translation
- **Get key:** https://rapidapi.com/
- **Setup:**
  1. Sign up for RapidAPI
  2. Subscribe to MyMemory Translation API
  3. Copy your RapidAPI key
  4. Add to `translateAPIKey`

### 4. Claude (Anthropic) API
- **Purpose:** AI conversation
- **Get key:** https://console.anthropic.com/settings/keys
- **Setup:**
  1. Sign up for Anthropic account
  2. Generate API key
  3. Add to `claudeAPIKey`

## Requirements
- iOS 17.0+
- Xcode 16.1+
- Valid API keys (all 4 required)

## Permissions
App will request:
- Microphone access
- Speech recognition access

## Features
- Voice recording with VOX (Voice Activity Detection)
- Speech-to-text (Google Speech API)
- Claude AI responses
- Text-to-speech (Google TTS)
- Real-time translation (English/Turkish)
- Multi-language support

## Security Note
**IMPORTANT:** Never commit `Constants.swift` with real API keys to GitHub!
- Keep your API keys private
- Add `Constants.swift` to `.gitignore`
- Use the template file for version control
