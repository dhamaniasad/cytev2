//
//  EpisodeView.swift
//  Cyte
//
//  Created by Shaun Narayan on 13/03/23.
//

import Foundation
import SwiftUI
import Charts
import AVKit
import Combine
import Vision

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var bundleCache: BundleCache
    @EnvironmentObject var episodeModel: EpisodeModel
    
    @State var player: AVPlayer
    @ObservedObject var episode: Episode
    
    @State private var isHoveringSave: Bool = false
    @State private var isHoveringExpand: Bool = false
    @State var filter: String
    @State var selected: Bool
    
    func offsetForEpisode(episode: Episode) -> Double {
        var offset_sum = 0.0
        let active_interval: AppInterval? = episodeModel.appIntervals.first { interval in
            if interval.episode.start == nil || interval.episode.end == nil { return false }
            offset_sum = offset_sum + (interval.episode.end!.timeIntervalSinceReferenceDate - interval.episode.start!.timeIntervalSinceReferenceDate)
            return episode.start == interval.episode.start
        }
        return offset_sum + (active_interval?.length ?? 0.0)
    }
    
    var playerView: some View {
        VStack {
            ZStack {
                VideoPlayer(player: player)
//                .frame(width: 360, height: 203)
                    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)) { _ in
                        //
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        
                    }
                    .padding(0)
                
            }
            .padding(0)
            HStack {
                VStack {
                    Text((episode.title ?? "")!.split(separator: " ").dropLast(6).joined(separator: " "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fontWeight(selected ? .bold : .regular)
                        .lineLimit(1)
                    Text((episode.start ?? Date()).formatted(date: .abbreviated, time: .standard) )
                        .font(SwiftUI.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    NavigationLink {
                        ZStack {
                            EpisodePlaylistView(player: player, secondsOffsetFromLastEpisode: offsetForEpisode(episode: episode) - player.currentTime().seconds, filter: filter
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain)
                    .opacity(isHoveringExpand ? 0.8 : 1.0)
                    .onHover(perform: { hovering in
                        self.isHoveringExpand = hovering
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    })

                    Image(systemName: episode.save ? "star.fill" : "star")
                        .onTapGesture {
                            episode.save = !episode.save
                            do {
                                try viewContext.save()
                            } catch {
                            }
                        }
                        .opacity(isHoveringSave ? 0.8 : 1.0)
                        .onHover(perform: { hovering in
                            self.isHoveringSave = hovering
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        })
                    Image(nsImage: bundleCache.getIcon(bundleID: (episode.bundle ?? Bundle.main.bundleIdentifier!)) )
                        .frame(width: 32, height: 32)
                }
                .padding(EdgeInsets(top: 10.0, leading: 0.0, bottom: 10.0, trailing: 0.0))
            }
        }
//        .frame(width: 360, height: 260)
    }


    var body: some View {
        playerView
            .accessibilityLabel("A single recording, with a video player, title, date/time and application context details.")
    }
}
