# AI Assistant - iOS App

Voice assistant with Claude AI integration.

## Setup

1. Open `AIAssistant.xcodeproj` in Xcode 16.1+
2. Edit `AIAssistant/Utils/Constants.swift` - add your Claude API key:
   ```swift
   static let claudeAPIKey = "sk-ant-api03-YOUR_KEY_HERE"
   ```
   Get key: https://console.anthropic.com/settings/keys
3. Select your team in Signing & Capabilities
4. Press Cmd+R to run

## Requirements

- iOS 17.0+
- Xcode 16.1+
- Claude API key

## Permissions

App will request:
- Microphone access
- Speech recognition access

## Features

- Voice recording
- Speech-to-text
- Claude AI responses
- Text-to-speech
- English/Turkish support
