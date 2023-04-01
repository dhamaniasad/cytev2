//
//  Faiss.swift
//  Cyte
//
//  Created by Shaun Narayan on 30/03/23.
//

import Foundation

extension String {

  func toPointer() -> UnsafePointer<UInt8>? {
    guard let data = self.data(using: String.Encoding.utf8) else { return nil }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    let stream = OutputStream(toBuffer: buffer, capacity: data.count)

    stream.open()
    data.withUnsafeBytes({ (p: UnsafePointer<UInt8>) -> Void in
      stream.write(p, maxLength: data.count)
    })

    stream.close()

    return UnsafePointer<UInt8>(buffer)
  }
}


class FAISS : ObservableObject {
    static let shared : FAISS = FAISS()
    var index: UnsafeMutablePointer<OpaquePointer?>?
    private let embeddingFile = homeDirectory().appendingPathComponent("Embeddings.index")
    static let EMBEDDING_SIZE: Int32 = 1536
    
    init() {
        setup()
    }
    
    func setup() {
        let type = "Flat"
        if FileManager.default.fileExists(atPath: embeddingFile.path(percentEncoded: false)) {
            faiss_read_index_fname(embeddingFile.path(percentEncoded: false).toPointer(), 0, index)
        } else {
            faiss_index_factory(index, FAISS.EMBEDDING_SIZE, type.toPointer(), METRIC_L2)
        }
    }
    
    func teardown() {
        if FileManager.default.fileExists(atPath: embeddingFile.path(percentEncoded: false)) {
            do {
                try FileManager.default.removeItem(atPath: embeddingFile.path(percentEncoded: false))
            } catch {}
        }
        faiss_write_index_fname(index?.pointee, embeddingFile.path(percentEncoded: false).toPointer())
        faiss_Index_free(index?.pointee)
    }
    
    func insert(embedding: [Float]) -> idx_t {
        let bufferPointer: UnsafeBufferPointer<Float> = embedding.withUnsafeBufferPointer { bufferPointer in
            return bufferPointer
        }
        faiss_Index_add(index?.pointee, 1, bufferPointer.baseAddress)
        return faiss_Index_ntotal(index?.pointee)
    }
    
    func search(by: [Float], k: Int = 8) -> ([idx_t], [Float]) {
        let byBufferPointer: UnsafeBufferPointer<Float> = by.withUnsafeBufferPointer { bufferPointer in
            return bufferPointer
        }
        var labels: [idx_t] = []
        var distances: [Float] = []
        labels.reserveCapacity(k)
        distances.reserveCapacity(k)
        let distancesBufferPointer: UnsafeMutableBufferPointer<Float> = distances.withUnsafeMutableBufferPointer { bufferPointer in
            return bufferPointer
        }
        let labelsBufferPointer: UnsafeMutableBufferPointer<idx_t> = labels.withUnsafeMutableBufferPointer { bufferPointer in
            return bufferPointer
        }
        faiss_Index_search(index?.pointee, 1, byBufferPointer.baseAddress, idx_t(k), distancesBufferPointer.baseAddress, labelsBufferPointer.baseAddress)
        return (labels, distances)
    }
}
