//
//  Analysis.swift
//  Cyte
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import Vision
import NaturalLanguage

class Analysis {
    static let shared = Analysis()
    private var pendingRequest: Bool = false
    private var dropouts: Int64 = 0
    
    //
    // Runs a chain of vision analysis (OCR then NLP) on the provided frame
    //
    func runOnFrame(frame: CapturedFrame) {
        if pendingRequest {
            dropouts += 1
            print("Drop frame due to overrun in process: \(dropouts)")
            return
        }
        pendingRequest = true
        // do analysis
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: frame.data!, orientation: .up)
        let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        if !utsname.isAppleSilicon {
            // fallback for intel
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
        }
        do {
            // Perform the text-recognition request.
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the requests: \(error).")
        }
    }
    
    //
    // Callback from vision OCR. Next run NLP and index keywords (nouns)
    //
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        guard let observations =
                request.results as? [VNRecognizedTextObservation] else {
            return
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
            return (candidate.string, VNImageRectForNormalizedRect(boundingBox,
                                                Int(1920),
                                                Int(1080)))
        }
        let text = recognizedStringsAndRects.reduce("") { (result, adding) in
            return "\(result) \(adding.0)"
        }
        Task {
            await Memory.shared.observe(what: text)
            pendingRequest = false
        }
    }
}
