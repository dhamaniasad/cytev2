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

extension CGRect: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(minX)
        hasher.combine(minY)
        hasher.combine(maxX)
        hasher.combine(maxY)
    }
}

extension View {
    func cutout<S: Shape>(_ shape: S) -> some View {
        self.clipShape(StackedShape(bottom: Rectangle(), top: shape), style: FillStyle(eoFill: true))
    }
}

struct StackedShape<Bottom: Shape, Top: Shape>: Shape {
    var bottom: Bottom
    var top: Top
    
    func path(in rect: CGRect) -> Path {
        return Path { path in
            path.addPath(bottom.path(in: rect))
            path.addPath(top.path(in: rect))
        }
    }
}

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var player: AVPlayer
    @ObservedObject var episode: Episode
    
    
    // @todo Ideally accept a subview so we don't need this data
    @State var intervals: [AppInterval]
    
    @State private var isHoveringSave: Bool = false
    @State private var isHoveringExpand: Bool = false
    @State var filter: String
    @State var selected: Bool
    
    func offsetForEpisode(episode: Episode) -> Double {
        var offset_sum = 0.0
        let active_interval: AppInterval? = intervals.first { interval in
            offset_sum = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
            return episode.start == interval.start
        }
        return offset_sum + (active_interval?.length ?? 0.0)
    }
    
    var playerView: some View {
        VStack {
            ZStack {
                VideoPlayer(player: player)
                .frame(width: 360, height: 203)
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
                    Text((episode.start ?? Date()).formatted(date: .abbreviated, time: .standard) )
                        .font(SwiftUI.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    NavigationLink {
                        ZStack {
                            EpisodePlaylistView(player: player, intervals: intervals, secondsOffsetFromLastEpisode: offsetForEpisode(episode: episode) - player.currentTime().seconds, filter: filter
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
                    Image(nsImage: getIcon(bundleID: (episode.bundle ?? Bundle.main.bundleIdentifier)!)!)
                }
                .padding(EdgeInsets(top: 10.0, leading: 0.0, bottom: 10.0, trailing: 0.0))
            }
        }
        .frame(width: 360, height: 260)
    }


    var body: some View {
        playerView
    }
}
