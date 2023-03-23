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

class Agent : ObservableObject {
    static let shared : Agent = Agent()
    static let promptTemplate = """
    Use the following pieces of context to answer the question at the end. If you don't know the answer, just say that you don't know, don't try to make up an answer.
        {context}
        Question: {question}
        Helpful Answer:
    """
    
    @Published var isConnected: Bool = false
    @Published public var chatLog : [(String, String, String)] = []
    
    init() {
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
        let embeddingUrl: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte").appendingPathComponent("Embeddings.coreml"))!
        
        // @todo load embeddings, query for best matches, format prompt template and make query
        do {
            let embeddings = try NLEmbedding(contentsOf: embeddingUrl)
            let jsonData = try Data(contentsOf: embeddingUrl)
            let cyteEmbeddings = try JSONDecoder().decode(CyteEmbeddings.self, from: jsonData)
            var context: String = ""
            embeddings.enumerateNeighbors(for: request, maximumCount: 5) { neighbor, distance in
                print("\(neighbor): \(distance.description)")
                // neighbor can be used to find the episode from sql, as well as the original text from the json
                let original = cyteEmbeddings.index[neighbor]?.text ?? ""
                context += original
                return true
            }
            let prompt = Agent.promptTemplate.replacing("{context}", with: context).replacing("{question}", with: request)
            let response = await LLM.shared.query(input: prompt)
            chatLog.append(("bot", "gpt3", response))
        } catch {
            
        }
    }
}
