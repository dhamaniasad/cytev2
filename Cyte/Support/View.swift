//
//  View.swift
//  Cyte
//
//  Created by Shaun Narayan on 9/04/23.
//

import Foundation
import AVKit
import SwiftUI
import Vision

extension Date {
    var dayOfYear: Int {
        return Calendar.current.ordinality(of: .day, in: .year, for: self)!
    }
}

struct StackedShape: Shape {
    let shapes: [AnyShape]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for shape in shapes {
            path.addPath(shape.path(in: rect))
        }
        return path
    }
}

extension View {
    func cutout<S: Shape>(_ shapes: [S]) -> some View {
        let anyShapes = shapes.map(AnyShape.init)
        return self.clipShape(StackedShape(shapes: anyShapes), style: FillStyle(eoFill: true))
    }
}

extension CGRect: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(minX)
        hasher.combine(minY)
        hasher.combine(maxX)
        hasher.combine(maxY)
    }
}

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

func procVisionResult(request: VNRequest, error: Error?) -> [(String, CGRect)] {
    guard let observations =
            request.results as? [VNRecognizedTextObservation] else {
        return []
    }
    let recognizedStringsAndRects: [(String, CGRect)] = observations.compactMap { observation in
        // Find the top observation.
        guard let candidate = observation.topCandidates(1).first else { return ("", .zero) }
        if observation.confidence < 0.45 { return ("", .zero) }
        
        // Find the bounding-box observation for the string range.
        let stringRange = candidate.string.startIndex..<candidate.string.endIndex
        let boxObservation = try? candidate.boundingBox(for: stringRange)
        
        // Get the normalized CGRect value.
        let boundingBox = boxObservation?.boundingBox ?? .zero
        
        // Convert the rectangle from normalized coordinates to image coordinates.
        return (candidate.string, boundingBox)
    }
    return recognizedStringsAndRects
}
