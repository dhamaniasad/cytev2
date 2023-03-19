//
//  StaticEpisodeView.swift
//  Cyte
//
//  Created by Shaun Narayan on 17/03/23.
//

import Foundation
import SwiftUI
import Charts
import AVKit
import Combine
import Vision

struct StaticEpisodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var asset: AVAsset
    @ObservedObject var episode: Episode
    
    @State var selection: Int = 0
    @ObservedObject var result: Interval
    @State var highlight: [CGRect] = []
    @State var thumbnail: CGImage?
    
    // @todo Ideally accept a subview so we don't need this data
    @State var intervals: [AppInterval]
    
    @State private var isHoveringSave: Bool = false
    @State private var isHoveringExpand: Bool = false
    @State private var isHoveringNext: Bool = false
    
    @State private var genTask: Task<Sendable, Error>?
    
    func generateThumbnail(offset: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime.zero;
        generator.requestedTimeToleranceAfter = CMTime.zero;
        do {
            thumbnail = try generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil)
            // Run through vision and store results
            let requestHandler = VNImageRequestHandler(cgImage: thumbnail!, orientation: .up)
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
        let selected = result
        // @todo replace map with loop if observations remain unused
        let _: [(String, CGRect)] = observations.compactMap { observation in
            // Find the top observation.
            guard let candidate = observation.topCandidates(1).first else { return ("", .zero) }
            
            // Find the bounding-box observation for the string range.
            let stringRange = candidate.string.startIndex..<candidate.string.endIndex
            let boxObservation = try? candidate.boundingBox(for: stringRange)
            
            // Get the normalized CGRect value.
            let boundingBox = boxObservation?.boundingBox ?? .zero
            
            if candidate.string.lowercased().contains((selected.concept?.name?.lowercased())!) {
                highlight.append(boundingBox)
            }
            
            // Convert the rectangle from normalized coordinates to image coordinates.
            return (candidate.string, VNImageRectForNormalizedRect(boundingBox,
                                                Int(1920),
                                                Int(1080)))
        }
    }
    
    func updateSelection() {
        selection = selection + 1
        if selection >= highlight.count {
            selection = 0
        }
    }
    
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
                if thumbnail != nil {
                    Image(thumbnail!, scale: 1.0, label: Text(""))
                        .resizable()
                        .frame(width: 360, height: 203)
                } else {
                    Spacer().frame(width: 360, height: 203)
                }
                
                GeometryReader { metrics in
                    if highlight.count > selection {
                        Color.black
                            .opacity(0.5)
                            .cutout(
                                RoundedRectangle(cornerRadius: 4)
                                    .scale(x: highlight[selection].width * 1.2, y: highlight[selection].height * 1.2)
                                    .offset(x:-180 + (highlight[selection].midX * 360), y:102 - (highlight[selection].midY * 203))
                                    
                            )
                    } else {
                        Color.black
                            .opacity(0.0)
                    }
                }
                
            }
            .padding(0)
            HStack {
                VStack {
                    Text(getApplicationNameFromBundleID(bundleID: episode.bundle ?? Bundle.main.bundleIdentifier!) ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text((result.from ?? Date()).formatted(date: .abbreviated, time: .standard) )
                        .font(SwiftUI.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    if highlight.count > 1 {
                        Text("\(selection+1) / \(highlight.count)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Image(systemName: "forward")
                            .onTapGesture {
                                updateSelection()
                            }
                            .opacity(isHoveringNext ? 0.8 : 1.0)
                            .onHover(perform: { hovering in
                                self.isHoveringNext = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
                    }
                    NavigationLink {
                        ZStack {
                            EpisodePlaylistView(player: AVPlayer(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(episode.title ?? "").mov"))!), intervals: intervals, secondsOffsetFromLastEpisode: offsetForEpisode(episode: episode) + (((result.from ?? Date()).timeIntervalSinceReferenceDate) - (episode.start ?? Date()).timeIntervalSinceReferenceDate), search: highlight.count > 0 ? result.concept?.name : nil
                            )
                        }
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
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
        .onAppear {
            genTask = Task {
                await generateThumbnail(offset: 0.0)
            }
        }
        .onDisappear {
            genTask?.cancel()
        }
    }


    var body: some View {
        playerView
    }
}
