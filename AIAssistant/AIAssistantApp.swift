//
//  AIAssistantApp.swift
//  AIAssistant
//
//  Created by AI Assistant
//  iOS 17.0+ / Xcode 16.1
//

import SwiftUI

@main
struct AIAssistantApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var claudeService = ClaudeService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(claudeService)
        }
    }
}
