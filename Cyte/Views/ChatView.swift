//
//  ChatView.swift
//  Cyte
//
//  Created by Shaun Narayan on 12/03/23.
//

import Foundation
import SwiftUI
import Highlightr
import AVKit

struct ChatView: View {
    @StateObject private var agent = Agent.shared
    @State var intervals: [AppInterval]
    
    @State private var isHoveringReturn: Bool = false
    
    private let highlightr = Highlightr()
    
    private func getUserInitials() -> String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        guard let components = formatter.personNameComponents(from: NSFullUserName()) else { return "M" }
        return formatter.string(from: components)
    }
    
    private func toArray(chat : (String, String, String)) -> EnumeratedSequence<[String.SubSequence]> {
        return chat.2.split(separator:"```").enumerated()
    }
    
    private func formatString(offset: Int, message: String) -> AttributedString {
        return offset % 2 == 1 ?
             AttributedString(highlightr!.highlight(message)!) :
                try! AttributedString(markdown:message, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }
    
    var messages: some View {
        ForEach(Array(agent.chatLog.enumerated()), id: \.offset) { index, chat in
            HStack {
                if chat.0 == "user" {
                    Image(systemName: "person")
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 15)
                                .foregroundColor(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                        )
                        
                } else {
                    Image(nsImage: getIcon(bundleID: Bundle.main.bundleIdentifier!)!)
                        .resizable()
                        .cornerRadius(15.0)
                        .frame(width: 30, height: 30)
                }
                VStack(alignment:.leading, spacing: 0) {
                    ForEach(Array(toArray(chat:chat)), id: \.offset) { subindex, subchat in
                        Text(formatString(offset:Int(subindex), message:String(subchat)))
                            .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .textSelection(.enabled)
                            .font(Font.body)
                            .lineLimit(100)
                    }
                    if agent.chatSources.count > index && chat.1.count > 0 && agent.chatSources[index]!.count > 0 {
                        Text("Sources:")
                            .padding()
//                            .multilineTextAlignment(.left)
                            .fontWeight(.bold)
                            .font(.caption)
                        ForEach(agent.chatSources[index]!.prefix(upTo: 6)) { episode in
                            EpisodeView(player: AVPlayer(url: urlForEpisode(start: episode.start, title: episode.title)), episode: episode, intervals: intervals, filter: "", selected: false)
                                .frame(width: 600, alignment: .leading)
                        }
                    }
                }
                
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: Alignment.leading)
            .background(
                RoundedRectangle(cornerRadius: String(chat.0) == "bot" ? 0 : 17)
                    .foregroundColor(String(chat.0) == "bot" ? .clear : Color(red: 255.0/255.0, green: 255.0/255.0, blue: 255.0/255.0)))
        }
    }
    
    var body: some View {
        withAnimation {
            VStack {
                Spacer().frame(height:40)
                HStack(alignment: .top ) {
                    VStack(alignment:.leading) {
                        Spacer().frame(height:10)
                        Button {
                            agent.reset()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.backward")
                                    .foregroundColor(.white)
                                Text("Return")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 4.0).foregroundColor(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0)))
                        .onHover(perform: { hovering in
                            self.isHoveringReturn = hovering
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        })
                        Spacer()
                    }
                    .frame(minWidth: 200, maxHeight: .infinity, alignment: .leading)
                    ScrollView {
                        VStack(spacing: 0) {
                            messages
                        }
                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 210))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
