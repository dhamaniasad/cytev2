//
//  EpisodePlaylistView.swift
//  Cyte
//
//  Created by Shaun Narayan on 13/03/23.
//

import Foundation
import SwiftUI
import Charts
import AVKit
import Combine

struct EpisodePlaylistView: View {
    
    @State var player: AVPlayer?
    @State private var thumbnailImages: [CGImage?] = []
    
    @State var intervals: [AppInterval]
    @State static var windowLengthInSeconds: Int = 60 * 2
    
    @State var secondsOffsetFromLastEpisode: Double = 0.0
    
    @State private var lastThumbnailRefresh: Date = Date()
    @State private var lastKnownInteractionPoint: CGPoint = CGPoint()
    @State private var lastX: CGFloat = 0.0
    @State private var subscriptions = Set<AnyCancellable>()
    
    private let timelineSize: CGFloat = 16
    
    func updateIntervals() {
        var offset = 0.0
        for i in 0..<(intervals.count - 1) {
            intervals[i].length = (intervals[i].end.timeIntervalSinceReferenceDate - intervals[i].start.timeIntervalSinceReferenceDate)
            intervals[i].offset = offset
            offset += intervals[i].length
            print("\(intervals[i].offset) ::: \(intervals[i].length)")
        }
    }
    
    func generateThumbnails(numThumbs: Int = 6) async {
        if intervals.count == 0 { return }
        let start: Double = secondsOffsetFromLastEpisode - Double(EpisodePlaylistView.windowLengthInSeconds)
        let end: Double = secondsOffsetFromLastEpisode
        let slide = EpisodePlaylistView.windowLengthInSeconds / numThumbs
        let times = stride(from: start, to: end, by: Double(slide))
        thumbnailImages.removeAll()
        for time in times {
            // get the AppInterval at this time, load the asset and find offset
            var offset_sum = 0.0
            let active_interval: AppInterval? = intervals.first { interval in
                let window_center = time
                let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
                let is_within = offset_sum <= window_center && next_offset >= window_center
                offset_sum = next_offset
                return is_within
            }
            if active_interval == nil || active_interval!.title.count == 0 {
                // placeholder thumb
                thumbnailImages.append(nil)
            } else {
                let asset = AVAsset(url: (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(active_interval!.title).mov"))!)
                
                let generator = AVAssetImageGenerator(asset: asset)
                generator.requestedTimeToleranceBefore = CMTime.zero;
                generator.requestedTimeToleranceAfter = CMTime.zero;
                do {
                    // turn the absolute time into a relative offset in the episode
                    let ep_len = (active_interval!.end.timeIntervalSinceReferenceDate - active_interval!.start.timeIntervalSinceReferenceDate)
                    let offset = secondsOffsetFromLastEpisode - (offset_sum - ep_len)
                    try thumbnailImages.append( generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil) )
                } catch {
                    print("Failed to generate thumbnail!")
                }
            }
        }
        lastThumbnailRefresh = Date()
        
    }
    
    func updateDisplayInterval(proxy: ChartProxy, geometry: GeometryProxy, gesture: DragGesture.Value) {
        if lastKnownInteractionPoint != gesture.startLocation {
            lastX = gesture.startLocation.x
            lastKnownInteractionPoint = gesture.startLocation
        }
        let chartWidth = geometry.size.width
        let deltaX = gesture.location.x - lastX
        lastX = gesture.location.x
        let xScale = CGFloat(Timeline.windowLengthInSeconds) / chartWidth
        let deltaSeconds = Double(deltaX) * xScale * 2
        print(deltaSeconds)
        
        let newStart = secondsOffsetFromLastEpisode + deltaSeconds
        if newStart > 0 {
            secondsOffsetFromLastEpisode = newStart
        }
        if (Date().timeIntervalSinceReferenceDate - lastThumbnailRefresh.timeIntervalSinceReferenceDate) > 0.5 {
            updateData()
        }
//        print(displayInterval)
    }
    
    func updateData() {
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions.removeAll()
        
        var offset_sum = 0.0
        let active_interval: AppInterval? = intervals.first { interval in
            let window_center = secondsOffsetFromLastEpisode
            let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
            let is_within = offset_sum <= window_center && next_offset >= window_center
            offset_sum = next_offset
            return is_within
        }
        
        // generate thumbs
        Task {
            await self.generateThumbnails()
        }
        
        if active_interval == nil || active_interval!.title.count == 0 {
            player = nil
            return
        }
        // reset the AVPlayer to the new asset
        player = AVPlayer(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(active_interval!.title).mov"))!)
        // seek to correct offset
        let ep_len = (active_interval!.end.timeIntervalSinceReferenceDate - active_interval!.start.timeIntervalSinceReferenceDate)
        let progress = secondsOffsetFromLastEpisode - (offset_sum - ep_len)
        let offset: CMTime = CMTime(seconds: progress, preferredTimescale: player!.currentTime().timescale)
        self.player!.seek(to: offset, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
    }
    
    func windowOffsetToCenter(of: AppInterval) -> Double {
        // I know this is really poorly written. I'm tired. I'll fix it when I see it again.
//        let interval_center = (of.start.timeIntervalSinceReferenceDate + of.end.timeIntervalSinceReferenceDate) / 2
//        let window_length = displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate
//        let portion = (interval_center - displayInterval.0.timeIntervalSinceReferenceDate) / window_length
//        return portion
        return 0.5
    }
    
    func playerEnded() {
        // Switch over to next interval. If it's empty, setup a timer to move time forward.

        
    }
    
    func startTimeForEpisode(interval: AppInterval) -> Double {
        return max(Double(secondsOffsetFromLastEpisode) + (Double(EpisodePlaylistView.windowLengthInSeconds) - interval.offset - interval.length), 0.0)
    }
    
    func endTimeForEpisode(interval: AppInterval) -> Double {
        return min(Double(EpisodePlaylistView.windowLengthInSeconds), Double(EpisodePlaylistView.windowLengthInSeconds) + Double(secondsOffsetFromLastEpisode) - Double(interval.offset))
    }
    
    var chart: some View {
        Chart {
            ForEach(intervals.filter { interval in
                return interval.offset <= (secondsOffsetFromLastEpisode + Double(EpisodePlaylistView.windowLengthInSeconds)) &&
                interval.offset >= (secondsOffsetFromLastEpisode - Double(EpisodePlaylistView.windowLengthInSeconds))
            }) { (interval: AppInterval) in
                BarMark(
                    xStart: .value("Start Time", startTimeForEpisode(interval: interval)),
                    xEnd: .value("End Time", endTimeForEpisode(interval: interval)),
                    y: .value("?", 0),
                    height: MarkDimension(floatLiteral: timelineSize * 2)
                )
                .foregroundStyle(interval.color)
                .cornerRadius(9.0)
            }
        }
        .frame(height: timelineSize * 4)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if self.player != nil {
                                    self.player!.pause()
                                }
                                updateDisplayInterval(proxy: proxy, geometry: geometry, gesture: gesture)
                            }
                            .onEnded { gesture in
                                updateData()
                            }
                    )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .onAppear {
            updateData()
            updateIntervals()
        }
    }

    var body: some View {
        VStack {
            HStack(alignment: .bottom) {
                Text("\(secondsOffsetFromLastEpisode)")
                    .frame(maxWidth: .infinity)
            }
            .font(Font.caption)
            .padding(10)
            VStack {
                ZStack {
                    chart
                    ZStack {
                        ForEach(intervals.filter { interval in
                            return interval.offset <= (secondsOffsetFromLastEpisode + Double(EpisodePlaylistView.windowLengthInSeconds))
                        }) { interval in
                            
                            GeometryReader { metrics in
                                HStack {
                                    if interval.bundleId.count > 0 {
                                        Image(nsImage: getIcon(bundleID: interval.bundleId)!)
                                            .resizable()
                                            .frame(width: timelineSize * 2, height: timelineSize * 2)
                                    }
                                }
                                .offset(CGSize(width: (windowOffsetToCenter(of:interval) * metrics.size.width) - timelineSize, height: timelineSize))
                            }
                        }
                    }
                    .frame(height: timelineSize * 4)
                }
                HStack(spacing: 0) {
                    ForEach(thumbnailImages, id: \.self) { image in
                        if image != nil {
                            Image(image!, scale: 1.0, label: Text(""))
                                .resizable()
                                .frame(width: 112*2, height: 56*2)
                        } else {
                            Rectangle()
                                .fill(.white)
                                .frame(width: 112*2, height: 56*2)
                        }
                    }
                }
            }
            VStack {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)) { _ in
                            //
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                            playerEnded()
                        }
                }
            
        }
    }
}
