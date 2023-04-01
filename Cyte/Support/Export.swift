//
//  Export.swift
//  Cyte
//
//  Created by Shaun Narayan on 30/03/23.
//

import Foundation
import AVKit

func makeTimelapse(episodes: [Episode], timelapse_len_seconds: Int = 60, reveal: Bool = true) -> AVAssetExportSession {
    let movie = AVMutableComposition()
    let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
//    let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

    var export_title: String = ""
    var sum_seconds: Double = 0.0
    for episode in episodes {
        let url = urlForEpisode(start: episode.start, title: episode.title)
        export_title += episode.title ?? ""
        
        let asset = AVURLAsset(url: url)
        
//        let assetAudioTrack = asset.tracks(withMediaType: .audio).first!
        let assetVideoTrack = asset.tracks(withMediaType: .video).first!
        let assetRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)
        
        do {
            let at = CMTime(value: CMTimeValue(sum_seconds), timescale: 1)
            
            try videoTrack?.insertTimeRange(assetRange, of: assetVideoTrack, at: at)
//            try audioTrack?.insertTimeRange(assetRange, of: assetAudioTrack, at: at)
        } catch {}
        sum_seconds += asset.duration.seconds
    }
    
//    let imageLayer = CALayer()
//    let videoSize: CGSize = (videoTrack?.naturalSize)!
//    let frame = CGRect(x: 0.0, y: 0.0, width: videoSize.width, height: videoSize.height)
//    let image = NSImage(named: "Watermark")
//    if let image = image {
//        var imageRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
//        imageLayer.contents = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
//    }
//    
//    imageLayer.frame = CGRect(x: 10, y: 10, width:90, height:50)
//    imageLayer.backgroundColor = .clear
//    imageLayer.opacity = 0.5
//
//    let videoLayer = CALayer()
//    videoLayer.frame = frame
//    let animationLayer = CALayer()
//    animationLayer.frame = frame
//    animationLayer.addSublayer(videoLayer)
//    animationLayer.addSublayer(imageLayer)
//
//    let videoComposition = AVMutableVideoComposition(propertiesOf: (videoTrack?.asset!)!)
//    videoComposition.renderSize = (videoTrack?.naturalSize)!
//    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: animationLayer)
//    let compi = AVMutableVideoCompositionInstruction()
//    compi.timeRange = CMTimeRangeMake(start: .zero, duration: movie.duration);
//    let ccc = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack!)
//    compi.layerInstructions = [ccc]
//    videoComposition.instructions = [compi]
    
    export_title = "\(export_title.hashValue).mov"
    movie.scaleTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: movie.duration), toDuration: CMTime(value: CMTimeValue(timelapse_len_seconds), timescale: 1))
    
    //create exporter
    let outputMovieURL: URL = homeDirectory().appendingPathComponent("Exports").appendingPathComponent(export_title)
    do {
        try FileManager.default.createDirectory(at: outputMovieURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        if FileManager.default.fileExists(atPath: outputMovieURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: outputMovieURL)
        }
    } catch { log.error("Failed to create export dir") }
    
    let exporter = AVAssetExportSession(asset: movie,
                                   presetName: AVAssetExportPresetHighestQuality)
    //configure exporter
    exporter?.outputURL = outputMovieURL
    exporter?.outputFileType = .mov
//    exporter?.videoComposition = videoComposition
    exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
        DispatchQueue.main.async {
            if let error = exporter?.error {
                print("failed \(error.localizedDescription)")
            } else {
                if reveal {
                    if FileManager.default.fileExists(atPath: outputMovieURL.path(percentEncoded: false)) {
                        NSWorkspace.shared.activateFileViewerSelecting([outputMovieURL])
                        print("movie has been exported to \(outputMovieURL)")
                    }
                }
            }
        }
    })
    
    return exporter!
}
