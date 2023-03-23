//
//  LLM.swift
//  Cyte
//
//  Created by Shaun Narayan on 23/03/23.
//

import Foundation
import OpenAIKit
import AsyncHTTPClient
import KeychainSwift

class LLM: ObservableObject {
    static let shared = LLM()
    
    private let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
    private var openAIClient: OpenAIKit.Client?
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
                    let configuration = Configuration(apiKey: apiKey, organization: organization)
                    openAIClient = OpenAIKit.Client(httpClient: httpClient, configuration: configuration)
                    isSetup = true
                    print("Setup OpenAI")
                } else {
                    openAIClient = nil
                }
            }
        }
    }
    
    func isFlagged(input: String) async -> Bool {
        do {
            let moderation = try await openAIClient!.moderations.createModeration(input: input)
            return moderation.results[0].flagged
        } catch {}
        return true
    }
    
    func embed(input: String) async -> [Float]? {
        if await isFlagged(input: input) { return nil }
        do {
            let embedding = try await openAIClient!.embeddings.create(input:input)
            var result: [Float]? = nil
            for embed in embedding.data {
                result = embed.embedding
            }
            return result
        } catch {
            return nil
        }
    }
    
    func query(input: String) async -> String {
        if await isFlagged(input: input) { return "Bad input" }
        do {
            let completion = try await openAIClient!.chats.create(
                model: Model.GPT3.gpt3_5Turbo,
                messages: [
                    .user(content: input)
                ]
            )
            var result = ""
            switch completion.choices[0].message {
                case .assistant(let content):
                    result = content;
                case .system(_):
                    break
                case .user(_):
                    break
            }
            return result
        } catch {
            return ""
        }
    }
}
