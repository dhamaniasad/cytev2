//
//  Agent.swift
//  Cyte
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import CoreGraphics
import Cocoa
import NaturalLanguage
import OpenAI
import KeychainSwift

class Agent : ObservableObject, EventSourceDelegate {
    static let shared : Agent = Agent()
    
    private var openAIClient: OpenAI?
    private let keychain = KeychainSwift()
    @Published var isSetup: Bool = false
    
    static let promptTemplate = """
    Use the following pieces of context to answer the question at the end. If you don't know the answer, just say that you don't know, don't try to make up an answer.
        {context}
        Question: {question}
        Helpful Answer:
    """
    
    static let chatPromptTemplate = """
    Assistant is a large language model trained by OpenAI.

    Assistant is designed to be able to assist with a wide range of tasks, from answering simple questions to providing in-depth explanations and discussions on a wide range of topics. As a language model, Assistant is able to generate human-like text based on the input it receives, allowing it to engage in natural-sounding conversations and provide responses that are coherent and relevant to the topic at hand.

    Assistant is constantly learning and improving, and its capabilities are constantly evolving. It is able to process and understand large amounts of text, and can use this knowledge to provide accurate and informative responses to a wide range of questions. Additionally, Assistant is able to generate its own text based on the input it receives, allowing it to engage in discussions and provide explanations and descriptions on a wide range of topics.

    Overall, Assistant is a powerful tool that can help with a wide range of tasks and provide valuable insights and information on a wide range of topics. Whether you need help with a specific question or just want to have a conversation about a particular topic, Assistant is here to assist.

    {history}
    Human: {question}
    Assistant:
    """
    
    @Published public var chatLog : [(String, String, String)] = []
    
    init() {
        setup()
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
                    openAIClient = OpenAI(apiToken: apiKey, callback: self)
                    isSetup = true
                    print("Setup OpenAI")
                } else {
                    openAIClient = nil
                }
            }
        }
    }
    
    func isFlagged(input: String) async -> Bool {
        let query = OpenAI.ModerationQuery(input: input, model: .textModerationLatest)
        var response: Bool = false
        do {
            let result = try await openAIClient!.moderations(query: query)
            response = result.results[0].flagged
        } catch {}
        return response
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
    
    func query(input: String) async -> Void {
        if await isFlagged(input: input) { return }
        let query = OpenAI.ChatQuery(model: .gpt3_5Turbo, messages: [.init(role: "user", content: input)], stream: true)
        openAIClient!.chats(query: query)
    }
    
    func onNewToken(token: String) {
        let chatId = chatLog.lastIndex(where: { log in
            return log.0 == "bot"
        })
        chatLog[chatId!].2.append(token.replacingOccurrences(of: "\\n", with: "\n"))
    }
    
    func observe(frame: CapturedFrame) {
        let ciImage = CIImage(cvPixelBuffer: frame.data!)
        let context = CIContext(options: nil)
        let width = CVPixelBufferGetWidth(frame.data!)
        let height = CVPixelBufferGetHeight(frame.data!)
        
        let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height))!
        
        let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
        let b64 = nsImage.tiffRepresentation?.base64EncodedString()
    }
    
    func index(path: URL) {
        //
    }
    
    func reset() {
        chatLog.removeAll()
    }
    
    func query(request: String) async {
        let embeddingUrl: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte").appendingPathComponent("Embeddings.json"))!
        let coremlUrl = embeddingUrl.deletingLastPathComponent().appendingPathComponent("Embeddings.coreml")
        
        await MainActor.run {
            chatLog.append(("user", "", request))
            chatLog.append(("bot", "gpt4", ""))
        }
        if false && FileManager.default.fileExists(atPath: embeddingUrl.path(percentEncoded: false)) {
            print("Runiing QA prompt")
            do {
                let embeddings = try NLEmbedding(contentsOf: coremlUrl)
                let jsonData = try Data(contentsOf: embeddingUrl)
                let cyteEmbeddings = try JSONDecoder().decode(CyteEmbeddings.self, from: jsonData)
                var context: String = ""
                let query_embedding: [Double] = await embed(input: request)!.map { Double($0) }
                embeddings.enumerateNeighbors(for: query_embedding, maximumCount: 5) { neighbor, distance in
                    print("\(neighbor): \(distance.description)")
                    // neighbor can be used to find the episode from sql, as well as the original text from the json
                    let original = cyteEmbeddings.index[neighbor]?.text ?? ""
                    context += original
                    return true
                }
                print(context)
                let prompt = Agent.promptTemplate.replacing("{context}", with: context).replacing("{question}", with: request)
                print(prompt)
                print("Query LLM")
                await query(input: prompt)
                print("Finish LLM")
//                chatLog.append(("bot", "gpt3", response))
            } catch { }
        } else {
            print("Runiing chat prompt")
            let prompt = Agent.chatPromptTemplate.replacing("{history}", with: "").replacing("{question}", with: request)
            print("Query LLM")
            await query(input: prompt)
            print("Finish LLM")
//            chatLog.append(("bot", "gpt3", response))
        }
    }
}
