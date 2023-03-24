//
//  LLM.swift
//  Cyte
//
//  Created by Shaun Narayan on 23/03/23.
//

import Foundation
import KeychainSwift
import OpenAI

class LLM: ObservableObject {
    static let shared = LLM()
    
    private var openAIClient: OpenAI?
    private let keychain = KeychainSwift()
    @Published var isSetup: Bool = false
    
    init() {
    }
    
    func setup(key: String? = nil) {
        if key != nil {
            keychain.set(key!, forKey: "CYTE_OPENAI_KEY")
        }
        let creds = keychain.get("CYTE_OPENAI_KEY")
        if creds != nil {
            let details = creds?.split(separator: "@")
            if (details?.count ?? 0) > 1 {
                let apiKey: String = String(details![0])
                let organization: String = String(details![1])
                if apiKey.count > 0 && organization.count > 0 {
                    openAIClient = OpenAI(apiToken: apiKey)
                    isSetup = true
                    print("Setup OpenAI")
                } else {
                    openAIClient = nil
                }
            }
        }
    }
    
    func isFlagged(input: String) async -> Bool {
        // @todo implement
        return false
    }
    
    func embed(input: String) async -> [Double]? {
        if await isFlagged(input: input) { return nil }
        let query = OpenAI.EmbeddingsQuery(model: .textEmbeddingAda, input: input)
        var response: [Double]? = nil
        do {
            let result = try await openAIClient!.embeddings(query: query)
            response = result.data[0].embedding
        } catch {}
        return response
    }
    
    func query(input: String) async -> String {
        if await isFlagged(input: input) { return "Bad input" }
        let query = OpenAI.ChatQuery(model: .gpt4, messages: [.init(role: "user", content: input)])
        var response = "Error"
        do {
            let result = try await openAIClient!.chats(query: query)
            response = result.choices[0].message.content
        } catch {}
        return response
    }
}
