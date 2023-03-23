//
//  LLM.swift
//  Cyte
//
//  Created by Shaun Narayan on 23/03/23.
//

import Foundation
import OpenAIKit
import AsyncHTTPClient

class LLM {
    static let shared = LLM()
    
    private let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
    private let openAIClient: OpenAIKit.Client?
    
    init() {
        var apiKey: String {
            ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
        }

        var organization: String {
            ProcessInfo.processInfo.environment["OPENAI_ORGANIZATION"]!
        }
        let configuration = Configuration(apiKey: apiKey, organization: organization)
        openAIClient = OpenAIKit.Client(httpClient: httpClient, configuration: configuration)
    }
    
    func isFlagged(input: String) async -> Bool {
        do {
            let moderation = try await openAIClient!.moderations.createModeration(input: input)
            return moderation.results[0].flagged
        } catch {}
        return true
    }
    
    func embed(input: String) async -> [Float]? {
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
