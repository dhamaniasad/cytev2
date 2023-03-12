//
//  ChatView.swift
//  Cyte
//
//  Created by Shaun Narayan on 12/03/23.
//

import Foundation
import SwiftUI
import Highlightr

struct ChatView: View {
    @StateObject private var agent = Agent.shared
    
    private let highlightr = Highlightr()
    
    private func getUserInitials() -> String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        guard let components = formatter.personNameComponents(from: NSFullUserName()) else { return "M" }
        return formatter.string(from: components)
    }
    
    private func toArray(chat : (String, String)) -> EnumeratedSequence<[String.SubSequence]> {
        return chat.1.split(separator:"```").enumerated()
    }
    
    private func formatString(offset: Int, message: String) -> AttributedString {
        return offset % 2 == 1 ?
             AttributedString(highlightr!.highlight(message)!) :
                try! AttributedString(markdown:message)
    }
    
    var body: some View {
        withAnimation {
            HStack(alignment: .bottom ) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(agent.chatLog.enumerated()), id: \.offset) { index, chat in
                            HStack {
                                if chat.0 == "user" {
                                    Text(getUserInitials())
                                        .frame(width: 50, height: 50)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .foregroundColor(.gray))
                                        .font(Font.title)
                                } else {
                                    Image(nsImage: getIcon(bundleID: Bundle.main.bundleIdentifier!)!)
                                        .resizable()
                                        .frame(width: 50, height: 50)
                                }
                                VStack(spacing: 0) {
//                                    ForEach(Array(toArray(chat)), id: \.offset) { subindex, subchat in
                                    Text(formatString(offset:0, message:chat.1))
                                        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                        .textSelection(.enabled)
                                        .font(Font.body)
                                        .lineLimit(100)
//                                    }
                                }
                                
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: Alignment.leading)
                            .background(
                                RoundedRectangle(cornerRadius: 0)
                                    .foregroundColor(chat.0 == "user" ? .clear : .white))
                            Divider()
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 10, leading: 100, bottom: 10, trailing: 100))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
