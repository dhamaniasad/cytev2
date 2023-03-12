//
//  Timeline.swift
//  Cyte
//
//  Created by Shaun Narayan on 6/03/23.
//

import Foundation
import SwiftUI
import Charts
import AVKit
import Combine

extension CMTime: Strideable {
    public func advanced(by n: Int) -> CMTime {
        return CMTime(seconds: self.seconds + Double(n), preferredTimescale: self.timescale)
    }

    public func distance(to other: CMTime) -> Int {
        return Int(CMTimeSubtract(other, self).seconds)
    }
}

struct AppInterval :Identifiable {
    var start: Date
    var end: Date
    var bundleId: String
    var title: String
    var color: Color = Color.gray
    var id: Int { "\(start.formatted()) - \(end.formatted())".hashValue }
    var offset: Double = 0.0
    var length: Double = 0.0
}

struct Timeline: View {
    
    @State var player: AVPlayer?
    @State private var thumbnailImages: [CGImage?] = []
    
    @State var intervals: [AppInterval]
    @State static var windowLengthInSeconds: Int = 60 * 30
    
    @State var displayInterval: (Date, Date) = (
        Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: -windowLengthInSeconds, to: Date())!,
        Date()
    )
    
    @State private var lastThumbnailRefresh: Date = Date()
    @State private var lastKnownInteractionPoint: CGPoint = CGPoint()
    @State private var lastX: CGFloat = 0.0
    @State private var subscriptions = Set<AnyCancellable>()
    
    private let timelineSize: CGFloat = 8
    
    func generateThumbnails(numThumbs: Int = 6) async {
        let start = CMTime(seconds: displayInterval.0.timeIntervalSinceReferenceDate, preferredTimescale: 1)
        let end = CMTime(seconds: displayInterval.1.timeIntervalSinceReferenceDate, preferredTimescale: 1)
        let slide = (end - start).seconds / Double(numThumbs)
        let times = stride(from: start, to: end, by: Int(slide))
        thumbnailImages.removeAll()
        for time in times {
            // get the AppInterval at this time, load the asset and find offset
            let active_interval: AppInterval? = intervals.first { interval in
                return time >= CMTime(seconds: interval.start.timeIntervalSinceReferenceDate, preferredTimescale: 1) && time <= CMTime(seconds: interval.end.timeIntervalSinceReferenceDate, preferredTimescale: 1)
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
                    let offset = time.seconds - active_interval!.start.timeIntervalSinceReferenceDate
                    try thumbnailImages.append( generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil) )
                } catch {
                    print("Failed to generate thumbnail!")
                }
            }
        }
        lastThumbnailRefresh = Date()
        
    }
    
    func fillEmptyIntervals() {
        // insert new intervals to fill the space between any non-contiguous intervals
        // Use a default color of Color.blue
        
        intervals.sort(by: { $0.start < $1.start })
        
        var newIntervals: [AppInterval] = []
        
        for i in 0..<(intervals.count - 1) {
            let interval = intervals[i]
            let nextInterval = intervals[i+1]
            if interval.end < nextInterval.start {
                let newInterval = AppInterval(start: interval.end, end: nextInterval.start, bundleId: "", title: "", color: Color.gray)
                newIntervals.append(newInterval)
            }
        }
        
        intervals.append(contentsOf: newIntervals)
        intervals.sort(by: { $0.start < $1.start })
        intervals.insert(AppInterval(start: Date(timeIntervalSinceReferenceDate: 0), end: intervals.first!.start, bundleId: Bundle.main.bundleIdentifier!, title: "", color: Color.gray), at: 0)
        intervals.append(AppInterval(start: intervals.last!.end, end: Date(), bundleId: Bundle.main.bundleIdentifier!, title: "", color: Color.gray))
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
        
        let newStart = Calendar.current.date(byAdding: .second, value: Int(-deltaSeconds), to: displayInterval.0)!
        let newEnd = Calendar.current.date(byAdding: .second, value: Int(-deltaSeconds), to: displayInterval.1)!
        if newEnd < Date() {
            displayInterval = (newStart, newEnd)
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
        
        let active_interval: AppInterval? = intervals.first { interval in
            let window_center = Date(timeIntervalSinceReferenceDate: displayInterval.0.timeIntervalSinceReferenceDate + (displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate) / 2)
            return interval.start <= window_center && interval.end >= window_center
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
        let center: Date = Date(timeIntervalSinceReferenceDate: displayInterval.0.timeIntervalSinceReferenceDate + (displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate) / 2)
        let progress = center.timeIntervalSinceReferenceDate - active_interval!.start.timeIntervalSinceReferenceDate
        let offset: CMTime = CMTime(seconds: progress, preferredTimescale: player!.currentTime().timescale)
        self.player!.seek(to: offset, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
    }
    
    func windowOffsetToCenter(of: AppInterval) -> Double {
        // I know this is really poorly written. I'm tired. I'll fix it when I see it again.
        let interval_center = (of.start.timeIntervalSinceReferenceDate + of.end.timeIntervalSinceReferenceDate) / 2
        let window_length = displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate
        let portion = (interval_center - displayInterval.0.timeIntervalSinceReferenceDate) / window_length
        return portion
    }
    
    func playerEnded() {
        // Switch over to next interval. If it's empty, setup a timer to move time forward.
        if player != nil {
            player!.pause()
        }
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [self] _ in
            // shift forward in time
            displayInterval = (
                Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: 1, to: displayInterval.0)!,
                Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: 1, to: displayInterval.1)!
            )
            let window_center = Date(timeIntervalSinceReferenceDate: displayInterval.0.timeIntervalSinceReferenceDate + (displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate) / 2)
            let active_interval: AppInterval? = intervals.first { interval in
                return interval.start <= window_center && interval.end >= window_center
            }
            if active_interval != nil && active_interval!.title.count != 0 {
                // moved into an episode
                updateData()
            }
        }
        .store(in: &subscriptions)
        
    }

    var body: some View {
        VStack {
            HStack(alignment: .bottom) {
                Text(displayInterval.0.formatted(date: .abbreviated, time: .shortened))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Date(timeIntervalSinceReferenceDate: displayInterval.0.timeIntervalSinceReferenceDate + (displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate) / 2).formatted(date: .omitted, time: .standard))
                    .frame(maxWidth: .infinity)
                Text(displayInterval.1.formatted(date: .abbreviated, time: .shortened))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(Font.caption)
            .padding(10)
            VStack {
                ZStack {
                    Chart {
                        ForEach(intervals.filter { interval in
                            (
                                (interval.start > displayInterval.0) && (interval.start < displayInterval.1)
                            ) ||
                            (
                                (interval.end > displayInterval.0) && (interval.end < displayInterval.1)
                            ) ||
                            (
                                (interval.start < displayInterval.0) && (interval.end > displayInterval.1)
                            )
                        }) { interval in
                            BarMark(
                                xStart: .value("Start Time", interval.start < displayInterval.0 ? displayInterval.0 : interval.start),
                                xEnd: .value("End Time", interval.end > displayInterval.1 ? displayInterval.1 : interval.end),
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
                        fillEmptyIntervals()
                        updateData()
                    }
                    ZStack {
                        ForEach(intervals.filter { interval in
                            (
                                (interval.start > displayInterval.0) && (interval.start < displayInterval.1)
                            ) ||
                            (
                                (interval.end > displayInterval.0) && (interval.end < displayInterval.1)
                            ) ||
                            (
                                (interval.start < displayInterval.0) && (interval.end > displayInterval.1)
                            )
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
                                .frame(width: 112, height: 56)
                        } else {
                            Rectangle()
                                .fill(.white)
                                .frame(width: 112, height: 56)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .foregroundColor(Color.white)
            )
            VStack {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)) { _ in
                            let window_center = Date(timeIntervalSinceReferenceDate: displayInterval.0.timeIntervalSinceReferenceDate + (displayInterval.1.timeIntervalSinceReferenceDate - displayInterval.0.timeIntervalSinceReferenceDate) / 2)
                            let active_interval: AppInterval = intervals.first { interval in
                                return interval.start <= window_center && interval.end >= window_center
                            }!
                            if player == nil {
                                // @todo understand what the interaction is between the two notifications causing it to be nil
                                return
                            }
                            let offset: CMTime = player!.currentTime()
                            let center = Date(timeIntervalSinceReferenceDate: offset.seconds + active_interval.start.timeIntervalSinceReferenceDate)
                            let newStart = Calendar.current.date(byAdding: .second, value: Int(-Double(Timeline.windowLengthInSeconds)/2.0), to: center)!
                            let newEnd = Calendar.current.date(byAdding: .second, value: Int(Double(Timeline.windowLengthInSeconds)/2.0), to: center)!
                            if newEnd < Date() {
                                displayInterval = (newStart, newEnd)
                            }
                            
                            if (Date().timeIntervalSinceReferenceDate - lastThumbnailRefresh.timeIntervalSinceReferenceDate) > 0.5 {
                                updateData()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                            playerEnded()
                        }
                }
            
        }
    }
}
