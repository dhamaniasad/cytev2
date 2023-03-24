//
//  Memory.swift
//  Cyte
//
//  Tracks active application context (driven by external caller)
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import AVKit
import OSLog
import Combine
import SQLite
import NaturalLanguage

class CyteInterval: ObservableObject, Identifiable {
    @Published var from: Date
    @Published var to: Date
    @Published var episode: Episode
    @Published var document: String
    
    init(from: Date, to: Date, episode: Episode, document: String) {
        self.from = from
        self.to = to
        self.episode = episode
        self.document = document
    }
    
    var id: String { "\(self.from.timeIntervalSinceReferenceDate)" }
}

func urlForEpisode(start: Date?, title: String?) -> URL {
    var url: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte"))!
    let components = Calendar.current.dateComponents([.year, .month, .day], from: start ?? Date())
    url = url.appendingPathComponent("\(components.year ?? 0)")
    url = url.appendingPathComponent("\(components.month ?? 0)")
    url = url.appendingPathComponent("\(components.day ?? 0)")
    url = url.appendingPathComponent("\(title ?? "").mov")
    return url
}

struct IntervalExpression {
    public static let id = Expression<Int64>("id")
    public static let from = Expression<Double>("from")
    public static let to = Expression<Double>("to")
    public static let episodeStart = Expression<Double>("episode_start")
    public static let document = Expression<String>("document")
}

struct FrameEmbedding : Codable {
    let text: String
    let vec: [Double]
}

struct CyteEmbeddings : Codable {
    var index : Dictionary<String, FrameEmbedding> = [:]
}

@MainActor
class Memory {
    static let shared = Memory()
    
    private var assetWriter : AVAssetWriter? = nil
    private var assetWriterInput : AVAssetWriterInput? = nil
    private var assetWriterAdaptor : AVAssetWriterInputPixelBufferAdaptor? = nil
    private var frameCount = 0
    private var currentStart: Date = Date()
    private var episode: Episode?
    private var shouldTrackFileChanges: Bool = utsname.isAppleSilicon ? true : false
    private var intervalDb: Connection?
    private var intervalTable: VirtualTable = VirtualTable("Interval")
    private var lastObservation: String = ""
    private var differ = DiffMatchPatch()
    private var embeddings: CyteEmbeddings = CyteEmbeddings()
    
    var currentContext : String = "Startup"
    
    init() {
        let unclosedFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        unclosedFetch.predicate = NSPredicate(format: "start == end")
        do {
            let embeddingUrl: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte").appendingPathComponent("Embeddings.json"))!
            let coremlUrl = embeddingUrl.deletingLastPathComponent().appendingPathComponent("Embeddings.coreml")
            if FileManager.default.fileExists(atPath: embeddingUrl.path(percentEncoded: false)) {
                do {
                    let jsonData = try Data(contentsOf: embeddingUrl)
                    embeddings = try JSONDecoder().decode(CyteEmbeddings.self, from: jsonData)
                    var nlembedding: [String: [Double]] = [:]
                    for (start_time, embedding) in embeddings.index {
                        nlembedding[start_time] = embedding.vec.map { Double($0) }
                    }
                    if FileManager.default.fileExists(atPath: coremlUrl.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(atPath: coremlUrl.path(percentEncoded: false))
                    }
                    try NLEmbedding.write(nlembedding, language: NLLanguage.english, revision: 0, to: embeddingUrl.deletingLastPathComponent().appendingPathComponent("Embeddings.coreml"))
                } catch { print(error) }
            }
            
            let url: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte").appendingPathComponent("CyteIntervals.sqlite3"))!
            intervalDb = try Connection(url.path(percentEncoded: false))
            do {
                let config = FTS4Config()
                    .column(IntervalExpression.from)
                    .column(IntervalExpression.to)
                    .column(IntervalExpression.episodeStart)
                    .column(IntervalExpression.document)
                    .languageId("lid")
                    .order(.desc)

                try intervalDb!.run(intervalTable.create(.FTS4(config), ifNotExists: true))
            }
            
            let fetched = try PersistenceController.shared.container.viewContext.fetch(unclosedFetch)
            for unclosed in fetched {
                PersistenceController.shared.container.viewContext.delete(unclosed)
            }
        } catch {
            
        }
    }
    
    static func getRecentFiles(earliest: Date) -> [(URL, Date)]? {
        let fileManager = FileManager.default
        let homeUrl = fileManager.homeDirectoryForCurrentUser
        
        var recentFiles: [(URL, Date)] = []
        let properties = [URLResourceKey.contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        
        guard let directoryEnumerator = fileManager.enumerator(at: homeUrl, includingPropertiesForKeys: properties, options: options, errorHandler: nil) else {
            return nil
        }
        
        for case let fileURL as URL in directoryEnumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(properties))
                if let modificationDate = resourceValues.contentModificationDate {
                    if !fileURL.hasDirectoryPath &&
                        (modificationDate > earliest) &&
                        !(
                            fileURL.pathComponents.contains("Movies") &&
                            fileURL.pathComponents.contains(Bundle.main.bundleIdentifier!) &&
                            fileURL.pathExtension != "html"
                        ) {
                        recentFiles.append((fileURL, modificationDate))
                    }
                }
            } catch {
                print("Error reading attributes for file at \(fileURL.path): \(error.localizedDescription)")
            }
        }
        
        recentFiles.sort(by: { $0.1 > $1.1 })
        return recentFiles
    }
    
    //
    // Check the currently active app, if different since last check
    // then close the current episode and start a new one
    //
    func updateActiveContext(windowTitles: Dictionary<String, String>) {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let context = front.bundleIdentifier ?? "Unnamed"
        if front.isActive && currentContext != context {
            if assetWriter != nil && assetWriterInput!.isReadyForMoreMediaData {
                closeEpisode()
            }
            currentContext = context
            let exclusion = Memory.shared.getOrCreateBundleExclusion(name: currentContext)
            if  assetWriter == nil && currentContext != Bundle.main.bundleIdentifier && exclusion.excluded == false {
                let title = windowTitles[currentContext] ?? front.localizedName ?? currentContext
                openEpisode(title: title)
            } else {
                print("Bypass exclusion context \(currentContext)")
            }
        }
    }
    
    //
    // Sets up a stream to disk
    //
    func openEpisode(title: String) {
        print("Open \(title)")
        
        currentStart = Date()
        let full_title = "\(title.replacingOccurrences(of: ":", with: ".")) \(currentStart.formatted(date: .abbreviated, time: .standard).replacingOccurrences(of: ":", with: "."))"
        let outputMovieURL = urlForEpisode(start: currentStart, title: full_title)
        do {
            try FileManager.default.createDirectory(at: outputMovieURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch { fatalError("Failed to create dir") }
        //create an assetwriter instance
        do {
            try assetWriter = AVAssetWriter(outputURL: outputMovieURL, fileType: .mov)
        } catch {
            abort()
        }
        //generate 1080p settings
        let settingsAssistant = AVOutputSettingsAssistant(preset: .preset1920x1080)?.videoSettings
        //create a single video input
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: settingsAssistant)
        //create an adaptor for the pixel buffer
        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput!, sourcePixelBufferAttributes: nil)
        //add the input to the asset writer
        assetWriter!.add(assetWriterInput!)
        //begin the session
        assetWriter!.startWriting()
        assetWriter!.startSession(atSourceTime: CMTime.zero)
        
        episode = Episode(context: PersistenceController.shared.container.viewContext)
        episode!.start = currentStart
        episode!.bundle = currentContext
        episode!.title = full_title
        episode!.end = currentStart
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func trackFileChanges(ep: Episode) {
        if shouldTrackFileChanges {
            // Make this follow a user preference, since it chews cpu
            let files = Memory.getRecentFiles(earliest: currentStart)
            for fileAndModified: (URL, Date) in files! {
                let doc = Document(context: PersistenceController.shared.container.viewContext)
                doc.path = fileAndModified.0
                doc.episode = ep
                do {
                    try PersistenceController.shared.container.viewContext.save()
                } catch {
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
                Agent.shared.index(path: doc.path!)
            }
        }
    }
    
    func reset()  {
        self.assetWriterInput = nil
        self.assetWriter = nil
        self.assetWriterAdaptor = nil
        self.frameCount = 0
        self.episode = nil
    }
    
    //
    // Save out the current file, create a DB entry and reset streams
    //
    func closeEpisode() {
        if assetWriter == nil {
            return
        }
        print("Close \(episode!.title)")
                
        //close everything
        assetWriterInput!.markAsFinished()
        
        if frameCount < 7 || currentContext.starts(with:Bundle.main.bundleIdentifier!) {
            assetWriter!.cancelWriting()
            delete(delete_episode: episode!)
            Logger().info("Supressed small episode for \(self.currentContext)")
        } else {
            let ep = self.episode!
            assetWriter!.finishWriting {
                self.trackFileChanges(ep:ep)
            }
            
            self.episode!.end = Date()
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        self.reset()
    }
    
    //
    // Push frame to encoder, run OCR
    //
    func addFrame(frame: CapturedFrame, secondLength: Int64) {
        if assetWriter != nil {
            if assetWriterInput!.isReadyForMoreMediaData {
                let frameTime = CMTimeMake(value: Int64(frameCount) * secondLength, timescale: 1)
                //append the contents of the pixelBuffer at the correct time
                assetWriterAdaptor!.append(frame.data!, withPresentationTime: frameTime)
                Analysis.shared.runOnFrame(frame: frame)
                frameCount += 1
            }
        }
    }

    func observe(what: String) async {
        let start = Date()
        // @todo track changes with diff and embed docs
        let result: NSMutableArray = differ.diff_main(ofOldString: lastObservation, andNewString: what)!
        differ.diff_cleanupSemantic(result)
        var edits: [(Int, String)] = []
        var added: String = ""
        // if the edit removes the entirety of the lastObservation, then consider it a new context, and embed the current document total
        var total_match = 0
        for res in result {
            let edit: (Int, String) = (Int((res as! Diff).operation.rawValue) - 2,
                        ((res as! Diff).text ?? ""))
            edits.append(edit)
            if edit.0 == 0 {
                total_match += edit.1.count
            }
            if edit.0 == 1 {
                added += edit.1
            }
        }
        
//        if total_match < 16 && lastObservation.count > 0 {
//            print("Frames share less than 8chars text content - closing and embedding document")
//            let embedding = await LLM.shared.embed(input: lastObservation)
//            embed(start: start, document:lastObservation, embedding:embedding!)
//        }
        
        let frameLength = 2
        let newItem = CyteInterval(from: start, to: Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: frameLength, to: start)!, episode: episode!, document: added)
        insert(interval: newItem)
        lastObservation = what
    }
    
    func embed(start: Date, document: String, embedding: [Double]) {
        // then add to coreml embed db, resave
        embeddings.index["\(start.timeIntervalSinceReferenceDate)"] = FrameEmbedding(text: document, vec: embedding)
        // overwrite on disk, recreate coreml model
        let embeddingUrl: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte").appendingPathComponent("Embeddings.json"))!
        let coremlUrl = embeddingUrl.deletingLastPathComponent().appendingPathComponent("Embeddings.coreml")
        do {
            if FileManager.default.fileExists(atPath: embeddingUrl.path(percentEncoded: false)) {
                try FileManager.default.removeItem(atPath: embeddingUrl.path(percentEncoded: false))
            }
            let jsonData = try JSONEncoder().encode(embeddings)
            try jsonData.write(to: embeddingUrl)
            var nlembedding: [String: [Double]] = [:]
            for (start_time, embedding) in embeddings.index {
                nlembedding[start_time] = embedding.vec.map { Double($0) }
            }
            if FileManager.default.fileExists(atPath: coremlUrl.path(percentEncoded: false)) {
                try FileManager.default.removeItem(atPath: coremlUrl.path(percentEncoded: false))
            }
            try NLEmbedding.write(nlembedding, language: NLLanguage.english, revision: 0, to: coremlUrl)
        } catch { print(error) }
        
    }

    func delete(delete_episode: Episode) {
        let intervals = intervalTable.filter(IntervalExpression.episodeStart == delete_episode.start!.timeIntervalSinceReferenceDate)
        PersistenceController.shared.container.viewContext.delete(delete_episode)
        do {
            try intervalDb!.run(intervals.delete())
            try PersistenceController.shared.container.viewContext.save()
            try FileManager.default.removeItem(at: urlForEpisode(start: delete_episode.start, title: delete_episode.title))
        } catch {
        }
    }
    
    func search(term: String) -> [CyteInterval] {
        let intervalMatch: QueryType = intervalTable.match("\(term)*")
        var result: [CyteInterval] = []
        do {
            for interval in try intervalDb!.prepare(intervalMatch) {
                let epStart: Date = Date(timeIntervalSinceReferenceDate: interval[IntervalExpression.episodeStart])
                
                let epFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
                epFetch.predicate = NSPredicate(format: "start == %@", epStart as CVarArg)
                var ep: Episode? = nil
                do {
                    let fetched = try PersistenceController.shared.container.viewContext.fetch(epFetch)
                    if fetched.count > 0 {
                        ep = fetched.first!
                    }
                    
                } catch {
                    //failed, fallback to create
                }
                
                let inter = CyteInterval(from: Date(timeIntervalSinceReferenceDate:interval[IntervalExpression.from]), to: Date(timeIntervalSinceReferenceDate:interval[IntervalExpression.to]), episode: ep!, document: interval[IntervalExpression.document])
                result.append(inter)
            }
        } catch { }
        return result
    }
    
    func insert(interval: CyteInterval) {
        do {
            let _ = try intervalDb!.run(intervalTable.insert(IntervalExpression.from <- interval.from.timeIntervalSinceReferenceDate,
                                                                 IntervalExpression.to <- interval.to.timeIntervalSinceReferenceDate,
                                                                 IntervalExpression.episodeStart <- interval.episode.start!.timeIntervalSinceReferenceDate,
                                                                 IntervalExpression.document <- interval.document
                                                                ))
        } catch {
            fatalError("insertion failed: \(error)")
        }
    }
    
    func getOrCreateBundleExclusion(name: String, excluded: Bool = false) -> BundleExclusion {
        let bundleFetch : NSFetchRequest<BundleExclusion> = BundleExclusion.fetchRequest()
        bundleFetch.predicate = NSPredicate(format: "bundle == %@", name)
        do {
            let fetched = try PersistenceController.shared.container.viewContext.fetch(bundleFetch)
            if fetched.count > 0 {
                return fetched.first!
            }
        } catch {
            //failed, fallback to create
        }
        let bundle = BundleExclusion(context: PersistenceController.shared.container.viewContext)
        bundle.bundle = name
        bundle.excluded = excluded
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
        }
        return bundle
    }
}
