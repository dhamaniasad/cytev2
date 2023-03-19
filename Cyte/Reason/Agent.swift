//
//  Agent.swift
//  Cyte
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import CoreGraphics
import Cocoa
import Starscream

class Agent : WebSocketDelegate, ObservableObject {
    static let shared : Agent = Agent()
    
    @Published var isConnected: Bool = false
    @Published public var chatLog : [(String, String, String)] = []
    
    private var socket : WebSocket
    private let secret = "34d87526839e9b49"
    
    init() {
        var request = URLRequest(url: URL(string: "http://localhost:7362/live?token=\(secret)")!)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }
    
    deinit {
        socket.disconnect()
    }
    
    func sendMessage(data: Dictionary<String, Any>) {
        do {
            let outgoing = try JSONSerialization.data(withJSONObject: data)
            socket.write(stringData: outgoing, completion: {
                print("Data sent")
            })
        } catch {
            //
        }
    }
    
    func reset(promptStyle: String = "agent") {
        chatLog.removeAll()
        sendMessage(data: [
            "type": "reset",
            "message": "\(promptStyle)"
        ])
    }
    
    func index(path: URL) {
        print("Indexing \(path.absoluteString)")
        sendMessage(data: [
            "type": "index",
            "message": path.absoluteString
        ])
    }
    
    func convertToDictionary(text: String) -> [String: String] {
        if let data = text.data(using: .utf8) {
            do {
                return try (JSONSerialization.jsonObject(with: data, options: []) as? [String: String])!
            } catch {
                print(error.localizedDescription)
            }
        }
        return [:]
    }
    
    func handle(message: String)  {
        let data = convertToDictionary(text: message)
        if data["sender"] == "bot" {
            //this could be a whole message or a single token, either way needs to make it's way to the UI
            if data["type"] == "start" {
                chatLog.append((data["sender"]!, data["botname"]!, ""))
            } else if data["type"] == "stream" {
                let chatId = chatLog.lastIndex(where: { log in
                    return log.0 == "bot"
                })
                chatLog[chatId!].2.append(data["message"]!.replacingOccurrences(of: "\\n", with: "\n"))
                chatLog[chatId!].1 = data["botname"]!
            } else if data["type"] == "info" {
//                chatLog.append((data["type"]!, "\(data["message"]!)"))
            } else if data["type"] == "end" {
                // filter out any info messages
                chatLog = chatLog.filter { chat in
                    return chat.0 != "info"
                }
            } else if data["type"] == "error" {
                
            }
        } else {
            // echo of your own message
            chatLog.append(("user", "", data["message"]!))
        }
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            isConnected = true
            print("websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            isConnected = false
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            print("Received text: \(string)")
            handle(message: string)
            break
        case .binary(let data):
            print("Received data: \(data.count)")
            handle(message: String(data:data, encoding: .utf8)!)
            break
        case .ping(_):
            break
        case .pong(_):
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            isConnected = false
        case .error(_):
            isConnected = false
            print("Attempt reconnection")
            socket.connect()
        }
    }
    
    func observe(frame: CapturedFrame) {
        let ciImage = CIImage(cvPixelBuffer: frame.data!)
        let context = CIContext(options: nil)
        let width = CVPixelBufferGetWidth(frame.data!)
        let height = CVPixelBufferGetHeight(frame.data!)
        
        let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height))!
        
        let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
        let b64 = nsImage.tiffRepresentation?.base64EncodedString()
        sendMessage(data: [
            "type": "observe",
            "message": b64!
        ])
    }
    
    func query(request: String) {
        sendMessage(data: [
            "type": "chat",
            "message": request
        ])
    }
}
