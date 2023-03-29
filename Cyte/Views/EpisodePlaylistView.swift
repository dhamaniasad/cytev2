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
import Vision

extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}

func secondsToReadable(seconds: Double) -> String {
    var (hr,  minf) = modf(seconds / 3600)
    let (min, secf) = modf(60 * minf)
    let days = Int(hr / 24)
    hr -= (Double(days) * 24.0)
    var res = ""
    if days > 0 {
        res += "\(days) days, "
    }
    if hr > 0 {
        res += "\(Int(hr)) hours, "
    }
    if min > 0 {
        res += "\(Int(min)) minutes, "
    }
    res += "\(Int(60 * secf)) seconds"
    return res
}

struct EpisodePlaylistView: View {
    
    @State var player: AVPlayer?
    @State private var thumbnailImages: [CGImage?] = []
    
    @State var intervals: [AppInterval]
    @State static var windowLengthInSeconds: Int = 60 * 2
    
    @State var secondsOffsetFromLastEpisode: Double
    
    @State private var lastKnownInteractionPoint: CGPoint = CGPoint()
    @State private var lastX: CGFloat = 0.0
    
    @State var filter: String
    @State var highlight: [CGRect] = []
    @State private var genTask: Task<(), Never>? = nil
    
    private let timelineSize: CGFloat = 16
    
    func updateIntervals() {
        var offset = 0.0
        for i in 0..<intervals.count {
            intervals[i].length = (intervals[i].end.timeIntervalSinceReferenceDate - intervals[i].start.timeIntervalSinceReferenceDate)
            intervals[i].offset = offset
            offset += intervals[i].length
//            print("\(intervals[i].offset) ::: \(intervals[i].length)")
//            print("\(startTimeForEpisode(interval: intervals[i])) --- \(endTimeForEpisode(interval: intervals[i]))")
            
        }
    }
    
    func generateThumbnails(numThumbs: Int = 1) async {
        if intervals.count == 0 { return }
        highlight.removeAll()
        let start: Double = secondsOffsetFromLastEpisode
        let end: Double = secondsOffsetFromLastEpisode + Double(EpisodePlaylistView.windowLengthInSeconds)
        let slide = EpisodePlaylistView.windowLengthInSeconds / numThumbs
        let times = stride(from: start, to: end, by: Double(slide)).reversed()
        thumbnailImages.removeAll()
        for time in times {
            // get the AppInterval at this time, load the asset and find offset
            // @todo getting active interval code is duplicated in this file. Extract to function
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
                let asset = AVAsset(url: urlForEpisode(start: active_interval!.start, title: active_interval!.title))
                
                let generator = AVAssetImageGenerator(asset: asset)
                generator.requestedTimeToleranceBefore = CMTime.zero;
                generator.requestedTimeToleranceAfter = CMTime.zero;
                do {
                    // turn the absolute time into a relative offset in the episode
                    let offset = offset_sum - secondsOffsetFromLastEpisode
                    try thumbnailImages.append( generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil) )
                } catch {
                    print("Failed to generate thumbnail!")
                }
            }
        }
        if thumbnailImages.last! != nil {
            // Run through vision and store results
            let requestHandler = VNImageRequestHandler(cgImage: thumbnailImages.last!!, orientation: .up)
            let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
            if !utsname.isAppleSilicon {
                // fallback for intel
                request.recognitionLevel = .fast
            }
            do {
                // Perform the text-recognition request.
                try requestHandler.perform([request])
            } catch {
                print("Unable to perform the requests: \(error).")
            }
            
        }
    }
    
    // @todo Function is duplicated 3 times (here, episodeview and analysis. needs to be Factored out)
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        guard let observations =
                request.results as? [VNRecognizedTextObservation] else {
            return
        }
        // @todo replace map with loop if observations remain unused
        let _: [(String, CGRect)] = observations.compactMap { observation in
            // Find the top observation.
            guard let candidate = observation.topCandidates(1).first else { return ("", .zero) }
            
            // Find the bounding-box observation for the string range.
            let stringRange = candidate.string.startIndex..<candidate.string.endIndex
            let boxObservation = try? candidate.boundingBox(for: stringRange)
            
            // Get the normalized CGRect value.
            let boundingBox = boxObservation?.boundingBox ?? .zero
            
            if candidate.string.lowercased().contains((filter.lowercased())) {
                highlight.append(boundingBox)
            }
            
            // Convert the rectangle from normalized coordinates to image coordinates.
            return (candidate.string, VNImageRectForNormalizedRect(boundingBox,
                                                Int(1920),
                                                Int(1080)))
        }
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
//        print(deltaSeconds)
        
        let newStart = secondsOffsetFromLastEpisode + deltaSeconds
        if newStart > 0 && newStart < ((intervals.last!.offset + intervals.last!.length)) {
            secondsOffsetFromLastEpisode = newStart
        }
        updateData()
    }
    
    func urlOfCurrentlyPlayingInPlayer(player : AVPlayer) -> URL? {
        return ((player.currentItem?.asset) as? AVURLAsset)?.url
    }
    
    func updateData() {
        var offset_sum = 0.0
        let active_interval: AppInterval? = intervals.first { interval in
            let window_center = secondsOffsetFromLastEpisode
            let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
            let is_within = offset_sum <= window_center && next_offset >= window_center
            offset_sum = next_offset
            return is_within
        }
        
        // generate thumbs
        if genTask != nil && !genTask!.isCancelled {
            genTask!.cancel()
        }
        genTask = Task {
            // debounce to 600ms
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
                await self.generateThumbnails()
            } catch { }
        }
        
        if active_interval == nil || active_interval!.title.count == 0 || player == nil {
            player = nil
            return
        }
        // reset the AVPlayer to the new asset
        let current_url = urlOfCurrentlyPlayingInPlayer(player: player!)
        let new_url = urlForEpisode(start: active_interval!.start, title: active_interval!.title)
        if current_url != new_url {
            player = AVPlayer(url: new_url)
        }
        // seek to correct offset
        let progress = (offset_sum) - secondsOffsetFromLastEpisode
        let offset: CMTime = CMTime(seconds: progress, preferredTimescale: player!.currentTime().timescale)
        self.player!.seek(to: offset, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
    }
    
    func windowOffsetToCenter(of: AppInterval) -> Double {
        // I know this is really poorly written. I'm tired. I'll fix it when I see it again.
        let interval_center = (startTimeForEpisode(interval: of) + endTimeForEpisode(interval: of)) / 2
        let window_length = Double(EpisodePlaylistView.windowLengthInSeconds)
        let portion = interval_center / window_length
        return portion
    }
    
    func playerEnded() {
        // @todo Switch over to next interval. If it's empty, setup a timer to move time forward.
        var offset_sum = 0.0
        var previous_interval: AppInterval?
        let window_center = secondsOffsetFromLastEpisode + 0.5
        let _: AppInterval? = intervals.first { interval in
            let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
            let is_within = offset_sum <= window_center && next_offset >= window_center
            offset_sum = next_offset
            if !is_within {
                previous_interval = interval
            }
            return is_within
        }
        if previous_interval != nil {
            // reset the AVPlayer to the new asset
            player = AVPlayer(url: urlForEpisode(start: previous_interval!.start, title: previous_interval!.title))
            self.player!.play()
            secondsOffsetFromLastEpisode = previous_interval!.offset + previous_interval!.length
        }
        
    }
    
    func startTimeForEpisode(interval: AppInterval) -> Double {
        return max(Double(secondsOffsetFromLastEpisode) + (Double(EpisodePlaylistView.windowLengthInSeconds) - interval.offset - interval.length), 0.0)
    }
    
    func endTimeForEpisode(interval: AppInterval) -> Double {
        let end =  min(Double(EpisodePlaylistView.windowLengthInSeconds), Double(secondsOffsetFromLastEpisode) + Double(EpisodePlaylistView.windowLengthInSeconds) - Double(interval.offset))
//        print("\(startTimeForEpisode(interval: interval)) --- \(end)")
        return end
    }
    
    func activeTime() -> String {
        var offset_sum = 0.0
        let active_interval: AppInterval? = intervals.first { interval in
            let window_center = secondsOffsetFromLastEpisode
            let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
            let is_within = offset_sum <= window_center && next_offset >= window_center
            offset_sum = next_offset
            return is_within
        }
        if active_interval == nil || player == nil {
            return Date().formatted()
        }
        return Date(timeIntervalSinceReferenceDate: active_interval!.start.timeIntervalSinceReferenceDate + player!.currentTime().seconds).formatted()
    }
    
    // @todo handle singlular/plural
    func humanReadableOffset() -> String {
        var offset_sum = 0.0
        let active_interval: AppInterval? = intervals.first { interval in
            let window_center = secondsOffsetFromLastEpisode
            let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
            let is_within = offset_sum <= window_center && next_offset >= window_center
            offset_sum = next_offset
            return is_within
        }
        
        let progress = offset_sum - secondsOffsetFromLastEpisode
        let anchor = Date().timeIntervalSinceReferenceDate - ((active_interval ?? intervals.last)!.end.timeIntervalSinceReferenceDate)
        let seconds = anchor - progress
        return "\(secondsToReadable(seconds: seconds)) ago"
    }
    
    
    var chart: some View {
        Chart {
            ForEach(intervals.filter { interval in
                return startTimeForEpisode(interval: interval) <= Double(EpisodePlaylistView.windowLengthInSeconds) &&
                endTimeForEpisode(interval: interval) >= 0
            }) { (interval: AppInterval) in
                BarMark(
                    xStart: .value("Start Time", startTimeForEpisode(interval: interval)),
                    xEnd: .value("End Time", endTimeForEpisode(interval: interval)),
                    y: .value("?", 0),
                    height: MarkDimension(floatLiteral: timelineSize * 2)
                )
                .foregroundStyle(interval.color)
                .cornerRadius(40.0)
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
            updateIntervals()
            updateData()
        }
    }
    
    var body: some View {
        GeometryReader { metrics in
            VStack {
                VStack {
                    ZStack(alignment: .topLeading) {
                        let width = (metrics.size.height - 100.0) / 9.0 * 16.0
                        let height = metrics.size.height - 100.0
                        VideoPlayer(player: player, videoOverlay: {
                            if highlight.count > 0 {
                                Color.black
                                    .opacity(0.5)
                                    .cutout(
                                        RoundedRectangle(cornerRadius: 4)
                                            .scale(x: highlight.first!.width * 1.2, y: highlight.first!.height * 1.2)
                                            .offset(x:-(width/2) + (highlight.first!.midX * width), y:(height/2) - (highlight.first!.midY * height))
                                        
                                    )
                            } else {
                                Color.black
                                    .opacity(0.0)
                            }
                            
                            
                        })
                        .frame(width: width, height: height)
                        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)) { _ in
                            if (player != nil && player!.error != nil) {
                                return
                            }
                            var offset_sum = 0.0
                            let active_interval: AppInterval? = intervals.first { interval in
                                let window_center = secondsOffsetFromLastEpisode
                                let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
                                let is_within = offset_sum <= window_center && next_offset >= window_center
                                offset_sum = next_offset
                                return is_within
                            }
                            let url = urlForEpisode(start: active_interval?.start, title: active_interval?.title)
                            if url != urlOfCurrentlyPlayingInPlayer(player: player!) {
                                // @todo hack to get around some form of off by one issue in the overall logic
                                // Active interval comes out as the next episode when the playhead is at the end of the video
                                secondsOffsetFromLastEpisode += 0.1
                            } else {
                                secondsOffsetFromLastEpisode = ((Double(active_interval!.offset) + Double(active_interval!.length)) - (player!.currentTime().seconds))
                            }
                            updateData()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                            //                                playerEnded()
                            player!.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        
                        
                    }
                    //                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .contextMenu {
                    Button {
                        var offset_sum = 0.0
                        let active_interval: AppInterval? = intervals.first { interval in
                            let window_center = secondsOffsetFromLastEpisode
                            let next_offset = offset_sum + (interval.end.timeIntervalSinceReferenceDate - interval.start.timeIntervalSinceReferenceDate)
                            let is_within = offset_sum <= window_center && next_offset >= window_center
                            offset_sum = next_offset
                            return is_within
                        }
                        let url = urlForEpisode(start: active_interval?.start, title: active_interval?.title).deletingLastPathComponent()
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path(percentEncoded: false))
                    } label: {
                        Label("Reveal in Finder", systemImage: "questionmark.folder")
                    }
                }
                VStack {
//                    HStack(spacing: 0) {
//                        ForEach(thumbnailImages, id: \.self) { image in
//                            if image != nil {
//                                Image(image!, scale: 1.0, label: Text(""))
//                                    .resizable()
//                                    .frame(width: 300, height: 170)
//                            } else {
//                                Rectangle()
//                                    .fill(.white)
//                                    .frame(width: 300, height: 170)
//                            }
//                        }
//                    }
//                    .frame(height: 170)
                    ZStack {
                        chart
                        ZStack {
                            ForEach(intervals.filter { interval in
                                return startTimeForEpisode(interval: interval) <= Double(EpisodePlaylistView.windowLengthInSeconds) &&
                                endTimeForEpisode(interval: interval) >= 0
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
                        .allowsHitTesting(false)
                    }
                    
                }
                HStack(alignment: .top) {
                    Text(activeTime())
                    Text(humanReadableOffset())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(Font.caption)
                Group {
                    Button(action: { secondsOffsetFromLastEpisode += 2.0; updateData(); }) {}
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button(action: { secondsOffsetFromLastEpisode = max(0.0, secondsOffsetFromLastEpisode - 2.0); updateData(); }) {}
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    Button(action: { secondsOffsetFromLastEpisode = 0; updateData(); }) {}
                        .keyboardShortcut(.return, modifiers: [])
                    Button(action: { if player == nil { return }; player!.isPlaying ? player!.pause() : player!.play(); }) {}
                        .keyboardShortcut(.space, modifiers: [])
                }.frame(maxWidth: 0, maxHeight: 0).opacity(0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
