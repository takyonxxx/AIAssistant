//
//  ClaudeService.swift
//  AIAssistant
//
//  Claude AI API integration service
//

import Foundation
import Combine

class ClaudeService: ObservableObject {
    @Published var isProcessing = false
    @Published var response = ""
    
    var onResponse: ((String) -> Void)?
    var onError: ((String) -> Void)?
    
    private let apiKey: String
    private let model = "claude-sonnet-4-5-20250929"
    private let apiURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    
    init(apiKey: String = Constants.claudeAPIKey) {
        self.apiKey = apiKey
    }
    
    // MARK: - Ask Claude
    
    func askClaude(question: String, maxWords: Int = 100) {
        guard !apiKey.isEmpty else {
            onError?("API key is empty!")
            return
        }
        
        guard !question.isEmpty else {
            onError?("Question is empty!")
            return
        }
        
        isProcessing = true
        
        // Prepare system prompt
        let systemPrompt = """
        You are a helpful assistant. \
        Always respond in the same language as the user's question (Turkish or English). \
        Keep your response concise and limit it to approximately \(maxWords) words. \
        Be direct and helpful.
        """
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": question
                        ]
                    ]
                ]
            ]
        ]
        
        guard let url = URL(string: apiURL) else {
            onError?("Invalid API URL")
            isProcessing = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            onError?("Failed to encode request: \(error.localizedDescription)")
            isProcessing = false
            return
        }
        
        print("Sending request to Claude API...")
        print("Question: \(question)")
        print("Max words: \(maxWords)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.onError?("Network error: \(error.localizedDescription)")
                }
                return
            }
            
            guard response is HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.onError?("Invalid response")
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.onError?("No data received")
                }
                return
            }
            
            // Parse response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Check for API errors
                    if let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        DispatchQueue.main.async {
                            self.onError?("Claude API: \(message)")
                        }
                        return
                    }
                    
                    // Extract response text
                    if let content = json["content"] as? [[String: Any]],
                       let firstContent = content.first,
                       let text = firstContent["text"] as? String {
                        
                        print("Response received: \(text)")
                        
                        DispatchQueue.main.async {
                            self.response = text
                            self.onResponse?(text)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.onError?("Invalid response format")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onError?("Failed to parse JSON response")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.onError?("JSON parsing error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // MARK: - Set API Key
    
    func setAPIKey(_ key: String) {
        // Update API key if needed
    }
}
