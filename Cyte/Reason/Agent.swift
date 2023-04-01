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
import XCGLogger

class Agent : ObservableObject, EventSourceDelegate {
    static let shared : Agent = Agent()
    
    private var openAIClient: OpenAI?
    private let keychain = KeychainSwift()
    @Published var isSetup: Bool = false
    
    static let promptTemplate = """
    Use the following pieces of context to answer the question at the end. The context includes transcriptions of my computer screen from running OCR on screenshots taken for every two seconds of computer activity. If you don't know the answer, just say that you don't know, don't try to make up an answer.
        Current Date/Time:
        {current}
        Context:
        {context}
        Question:
        {question}
        Helpful Answer:
    """
    
    static let contextTemplate = """
    Results from OCR on a screenshot taken at {when}:
    {ocr}
    
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
    @Published public var chatSources : [[Episode]?] = []
    
    init() {
        setup()
    }
    
    func setup(key: String? = nil) {
        if key != nil {
            keychain.set(key!, forKey: "CYTE_OPENAI_KEY")
        }
        let apiKey = keychain.get("CYTE_OPENAI_KEY")
        if apiKey != nil {
            openAIClient = OpenAI(apiToken: apiKey!, callback: self)
            isSetup = true
            log.info("Setup OpenAI")
        } else {
            openAIClient = nil
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
        let query = OpenAI.ChatQuery(model: .gpt4, messages: [.init(role: "user", content: input)], stream: true)
        openAIClient!.chats(query: query)
    }
    
    func onNewToken(token: String) {
        let chatId = chatLog.lastIndex(where: { log in
            return log.0 == "bot"
        })
        chatLog[chatId!].2.append(token.replacingOccurrences(of: "\\n", with: "\n"))
    }
    
    func onStreamDone() {
        let chatId = chatLog.lastIndex(where: { log in
            return log.0 == "bot"
        })
        chatLog[chatId!].1 = "gpt4"
    }
    
    func index(path: URL) {
        // @todo if the file type is supported, decode it and embed
    }
    
    func reset() {
        openAIClient!.stop()
        chatLog.removeAll()
        chatSources.removeAll()
    }
    
    @MainActor
    func query(request: String) async {
        var cleanRequest = request
        var force_chat = false
        if request.starts(with: "chat ") {
            force_chat = true
            cleanRequest = String(request.dropFirst("chat ".count))
        }
        chatLog.append(("user", "", cleanRequest))
        chatSources.append([])
        chatLog.append(("bot", "", ""))
        chatSources.append([])
        
        var context: String = ""
        let maxContextLength = (8000 * 3 /* rough token len */) - Agent.promptTemplate.count
        var foundEps: [Episode] = []
        var concepts: [String] = []
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = request
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        tagger.enumerateTags(in: request.startIndex..<request.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            if let tag = tag {
                // if verb or noun
                if tag.rawValue == "Noun" {
                    let concept = request[tokenRange]
                    concepts.append(String(concept))
                }
            }
            return true
        }
        if concepts.count == 0 { concepts.append(request) }
        var intervals = Memory.shared.search(term: concepts.joined(separator: " AND "))
        if intervals.count == 0 {
            print("Fallback to full search")
            intervals = Memory.shared.search(term: "")
        }
        if !force_chat {
            // semantic search
            let query_embedding: [Double] = await embed(input: request)!
            let results: ([idx_t], [Float]) = FAISS.shared.search(by: query_embedding.map{Float($0)}, k: 8)
            for idx in results.0 {
                let embedding = Memory.shared.lookupEmbedding(index: idx)
                let foundDate = Date(timeIntervalSinceReferenceDate: embedding!.time)
                let epFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
                epFetch.predicate = NSPredicate(format: "start < %@ AND end > %@", foundDate as CVarArg, foundDate as CVarArg)
                do {
                    let fetched = try PersistenceController.shared.container.viewContext.fetch(epFetch)
                    let new_context = Agent.contextTemplate.replacing("{when}", with: foundDate.formatted()).replacing("{ocr}", with: embedding!.text)
                    if context.count + new_context.count < maxContextLength {
                        context += new_context
                        if fetched.count > 0 {
                            foundEps.append(fetched.first!)
                        }
                    }
                } catch {}
            }
            
            // syntactic search
            for interval in intervals {
                if interval.document.count > 100 {
                    let new_context = Agent.contextTemplate.replacing("{when}", with: interval.from.formatted()).replacing("{ocr}", with: interval.document)
                    if context.count + new_context.count < maxContextLength {
                        context += new_context
                        foundEps.append(interval.episode)
                    }
                }
            }
            
            let prompt = Agent.promptTemplate.replacing("{current}", with: Date().formatted()).replacing("{context}", with: context).replacing("{question}", with: request)
            print(prompt)
            log.info(prompt)
            await query(input: prompt)
            
            let chatId = chatLog.lastIndex(where: { log in
                return log.0 == "bot"
            })
            chatSources[chatId!]!.append(contentsOf: Array(Set(foundEps)))
        } else {
            var history: String = ""
            for chat in chatLog {
                history = """
                    \(history)
                    \(chat.0 == "bot" ? "Assistant: " : "Human: ")\(chat.2)
                """
            }
            let prompt = Agent.chatPromptTemplate.replacing("{history}", with: history).replacing("{question}", with: cleanRequest)
            log.info(prompt)
            await query(input: prompt)
        }
    }
}
