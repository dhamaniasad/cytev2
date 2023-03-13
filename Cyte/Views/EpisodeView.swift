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

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var player: AVPlayer
    @State private var thumbnailImage: CGImage?
    @State var episode: Episode
    
    @State var selection: Int = 0
    @State var results: [Interval]
    // @todo Ideally accept a subview so we don't need this data
    @State var intervals: [AppInterval]
    @State var highlight: [CGRect] = []
    
    @State var showDetail: Bool = false
    
    func generateThumbnail(offset: Double) async {
        let asset = AVAsset(url: (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(episode.title ?? "").mov"))!)
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime.zero;
        generator.requestedTimeToleranceAfter = CMTime.zero;
        do {
            try thumbnailImage = generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil)
            // Run through vision and store results
            let requestHandler = VNImageRequestHandler(cgImage: thumbnailImage!, orientation: .up)
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
        } catch {
            print("Failed to generate thumbnail!")
        }
    }
    
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        guard let observations =
                request.results as? [VNRecognizedTextObservation] else {
            return
        }
        highlight.removeAll()
        let selected = results[selection]
        let recognizedStringsAndRects: [(String, CGRect)] = observations.compactMap { observation in
            // Find the top observation.
            guard let candidate = observation.topCandidates(1).first else { return ("", .zero) }
            
            // Find the bounding-box observation for the string range.
            let stringRange = candidate.string.startIndex..<candidate.string.endIndex
            let boxObservation = try? candidate.boundingBox(for: stringRange)
            
            // Get the normalized CGRect value.
            let boundingBox = boxObservation?.boundingBox ?? .zero
            
            if candidate.string.lowercased().contains((selected.concept?.name?.lowercased())!) {
                print(boundingBox)
                highlight.append(boundingBox)
            }
            
            // Convert the rectangle from normalized coordinates to image coordinates.
            return (candidate.string, VNImageRectForNormalizedRect(boundingBox,
                                                Int(1920),
                                                Int(1080)))
        }
        let text = recognizedStringsAndRects.reduce("") { (result, adding) in
            return "\(result) \(adding.0)"
        }
        // save bboxes related to current matched interval for display
//        print(text)
    }
    
    func updateSelection() {
        if selection < results.count {
            let selected = results[selection]
            let target = (selected.from ?? Date()).timeIntervalSinceReferenceDate - (episode.start ?? Date()).timeIntervalSinceReferenceDate
            Task {
                await generateThumbnail(offset: target)
            }
//            print("Seeking to \(target)")
            player.seek(to: CMTime(seconds: target, preferredTimescale: 1), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    var playerView: some View {
        VStack {
            if results.count > 0 {
                HStack {
                    Button {
                        selection = max(0, selection-1)
                        updateSelection()
                    } label: {
                        Text("Previous")
                    }
                    Text("\(selection+1) of \(results.count) matches")
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button {
                        selection = max(0, min(results.count-1, selection+1))
                        updateSelection()
                    } label: {
                        Text("Next")
                    }
                }
            }
            ZStack {
                VideoPlayer(player: player)
                    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)) { _ in
                        //
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        
                    }
                    .padding(0)
                GeometryReader { metrics in
                    ZStack {
                        ForEach(highlight, id:\.self) { box in
                            Rectangle()
                                .frame(width: box.width * metrics.size.width, height: box.height * metrics.size.height)
                                .position(x: box.minX * metrics.size.width, y: box.minY * metrics.size.height)
                                .foregroundColor(.yellow)
                                .opacity(0.5)
                        }
                    }
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(0)
            HStack {
                VStack {
                    Text(getApplicationNameFromBundleID(bundleID: episode.bundle ?? Bundle.main.bundleIdentifier!) ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text((episode.start ?? Date()).formatted(date: .abbreviated, time: .standard) )
                        .font(SwiftUI.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    NavigationLink {
                        ZStack {
                            EpisodePlaylistView(player: player, intervals: intervals, secondsOffsetFromLastEpisode: ((intervals.first?.end ?? Date()).timeIntervalSinceReferenceDate) - (episode.start ?? Date()).timeIntervalSinceReferenceDate
                            )
                        }
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                    }
                    .buttonStyle(.plain)

                    Image(systemName: episode.save ? "star.fill" : "star")
                        .onTapGesture {
                            episode.save = !episode.save
                            do {
                                try viewContext.save()
                            } catch {
                            }
                        }
                    Image(nsImage: getIcon(bundleID: (episode.bundle ?? Bundle.main.bundleIdentifier)!)!)
                }
            }
        }.frame(height: 300)
    }


    var body: some View {
        playerView
    }
}
