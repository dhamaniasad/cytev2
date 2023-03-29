///
///  Memory.swift
///  Cyte
///
///  Created by Shaun Narayan on 3/03/23.
///

import Foundation
import AVKit
import OSLog
import Combine
import SQLite
import NaturalLanguage

///
/// CoreData style wrapper for Intervals so it is observable in the UI
///
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

func homeDirectory() -> URL {
    let defaults = UserDefaults.standard
    let home = defaults.string(forKey: "CYTE_HOME")
    if home != nil && FileManager.default.fileExists(atPath: home!) {
        return URL(filePath: home!)
    }
    let url: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte"))!
    return url
}

///
/// Format the title for an episode given its start time and unformatted title
///
func urlForEpisode(start: Date?, title: String?) -> URL {
    var url: URL = homeDirectory()
    let components = Calendar.current.dateComponents([.year, .month, .day], from: start ?? Date())
    url = url.appendingPathComponent("\(components.year ?? 0)")
    url = url.appendingPathComponent("\(components.month ?? 0)")
    url = url.appendingPathComponent("\(components.day ?? 0)")
    url = url.appendingPathComponent("\(title ?? "").mov")
    return url
}

func revealEpisode(episode: Episode) {
    let url = urlForEpisode(start: episode.start, title: episode.title)
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

///
/// Helper struct for accessing Interval fields from result sets
///
struct IntervalExpression {
    public static let id = Expression<Int64>("id")
    public static let from = Expression<Double>("from")
    public static let to = Expression<Double>("to")
    public static let episodeStart = Expression<Double>("episode_start")
    public static let document = Expression<String>("document")
}

///
/// Wrapper for DB embeddings
///
struct CyteEmbedding : Codable {
    let time: Double
    let text: String
    let vec: [Double]
}

///
///  Tracks active application context (driven by external caller)
///  Opens, encodes and closes the video stream, triggers analysis on frames
///  and indexes the resultant information for search
///
@MainActor
class Memory {
    static let shared = Memory()
    
    /// Intra-episode/context processing
    private var assetWriter : AVAssetWriter? = nil
    private var assetWriterInput : AVAssetWriterInput? = nil
    private var assetWriterAdaptor : AVAssetWriterInputPixelBufferAdaptor? = nil
    private var frameCount = 0
    private var currentStart: Date = Date()
    private var episode: Episode?
    private var intervalDb: Connection?
    private var intervalTable: VirtualTable = VirtualTable("Interval")
    
    /// Context change tracking/indexing
    private var embeddingTable: Table = Table("Embedding")
    private var lastObservation: String = ""
    private var differ = DiffMatchPatch()
    static private var embeddingSize = 1536//openai ada
    
    /// Intel fallbacks - due to lack of hardware acelleration for video encoding and frame analysis, tradeoffs must be made
    private var shouldTrackFileChanges: Bool = true
    static let secondsBetweenFrames : Int = utsname.isAppleSilicon ? 2 : 4
    
    var currentContext : String = "Startup"
    
    ///
    /// Close any in-progress episodes (in case Cyte was not properly shut down)
    /// Set up the aux database for FTS and embeddings
    ///
    init() {
        let unclosedFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        unclosedFetch.predicate = NSPredicate(format: "start == end")
        do {
            let url: URL = homeDirectory().appendingPathComponent("CyteMemory.sqlite3")
            intervalDb = try Connection(url.path(percentEncoded: false))
            do {
                let config = FTS4Config()
                    .column(IntervalExpression.from, [.unindexed])
                    .column(IntervalExpression.to, [.unindexed])
                    .column(IntervalExpression.episodeStart, [.unindexed])
                    .column(IntervalExpression.document)
                    .languageId("lid")
                    .order(.desc)

                try intervalDb!.run(intervalTable.create(.FTS4(config), ifNotExists: true))
            }
            do {
                try intervalDb!.run(embeddingTable.create(ifNotExists: true) { t in
                    for i in 1...Memory.embeddingSize {
                        let dexp = Expression<Double>("d\(i)")
                        t.column(dexp)
                    }
                    t.column(Expression<Double>("episode_start"))
                    t.column(Expression<String>("fulltext"))
                })
            }
            
            let fetched = try PersistenceController.shared.container.viewContext.fetch(unclosedFetch)
            for unclosed in fetched {
                PersistenceController.shared.container.viewContext.delete(unclosed)
            }
        } catch {
            
        }
    }
    
    func getEmbeddings() -> [CyteEmbedding] {
        let startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -90, to:Date())!
        let embeddingMatch: QueryType = embeddingTable.filter(Expression<Double>("episode_start") > startDate.timeIntervalSinceReferenceDate)
        var result: [CyteEmbedding] = []
        do {
            for embedding in try intervalDb!.prepare(embeddingMatch) {
                var vec: [Double] = []
                for i in 1...Memory.embeddingSize {
                    vec.append(embedding[Expression<Double>("d\(i)")])
                }
                let embed = CyteEmbedding(time: embedding[Expression<Double>("episode_start")], text: embedding[Expression<String>("fulltext")], vec: vec)
                result.append(embed)
                
            }
        } catch {}
        return result
    }
    
    func getEmbedding(when: Double) -> CyteEmbedding? {
        let embeddingMatch: QueryType = embeddingTable.filter(Expression<Double>("episode_start") == when)
        do {
            for embedding in try intervalDb!.prepare(embeddingMatch) {
                var vec: [Double] = []
                for i in 1...Memory.embeddingSize {
                    vec.append(embedding[Expression<Double>("d\(i)")])
                }
                let embed = CyteEmbedding(time: embedding[Expression<Double>("episode_start")], text: embedding[Expression<String>("fulltext")], vec: vec)
                return embed
                
            }
        } catch {}
        return nil
    }
    
    func rebuildIndex() {
        let embeddings = getEmbeddings()
        let coremlUrl: URL = homeDirectory().appendingPathComponent("Embeddings.coreml")
        do {
            var nlembedding: [String: [Double]] = [:]
            for embedding in embeddings {
                nlembedding["\(embedding.time)"] = embedding.vec
            }
            if FileManager.default.fileExists(atPath: coremlUrl.path(percentEncoded: false)) {
                try FileManager.default.removeItem(atPath: coremlUrl.path(percentEncoded: false))
            }
            try NLEmbedding.write(nlembedding, language: NLLanguage.english, revision: 0, to: coremlUrl)
        } catch { print(error) }
    }
    
    ///
    /// Enumerates target directories and filters by last edit time.
    /// This is imperfect for a number of reasons, it is very low granularity for long episodes
    /// it is extremely processor intensive and slow
    ///
    /// Don't think Apple allows file change tracking via callback at such a detailed level,
    /// however surely there is some way to make use of Spotlight cache info on recently edited files
    /// which is a tab in Finder to avoid enumeration?
    ///
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
    
    ///
    /// Check the currently active app, if different since last check
    /// then close the current episode and start a new one
    /// Ignores the main bundle (Cyte) - creates sometimes undiscernable
    /// memories with many layers of picture in picture
    ///
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
                var title: String = windowTitles[currentContext] ?? ""
                if title.trimmingCharacters(in: .whitespacesAndNewlines).count == 0 {
                    title = front.localizedName ?? currentContext
                }
                openEpisode(title: title)
            } else {
                print("Bypass exclusion context \(currentContext)")
            }
        }
    }
    
    ///
    /// Sets up an MPEG4 stream to disk, HD resolution
    ///
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
    
    ///
    /// Saves all files edited within the episodes interval (as per last edit time)
    /// to the index for querying
    ///
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
    
    ///
    /// Helper function for closeEpisode, clear values
    ///
    private func reset()  {
        self.assetWriterInput = nil
        self.assetWriter = nil
        self.assetWriterAdaptor = nil
        self.frameCount = 0
        self.episode = nil
    }
    
    ///
    /// Save out the current file, create a DB entry and reset streams.
    ///
    func closeEpisode() {
        if assetWriter == nil {
            return
        }
                
        //close everything
        assetWriterInput!.markAsFinished()
        if frameCount < 2 || currentContext.starts(with:Bundle.main.bundleIdentifier!) {
            assetWriter!.cancelWriting()
            delete(delete_episode: episode!)
            log.info("Supressed small episode for \(self.currentContext)")
        } else {
            let ep = self.episode!
            assetWriter!.finishWriting {
                if (self.frameCount * Memory.secondsBetweenFrames) > 90 {
                    self.trackFileChanges(ep:ep)
                } else {
                    print("Skip file tracking for small episode")
                }
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
        self.runRetention()
    }
    
    private func runRetention() {
        // delete any episodes outside retention period
        let defaults = UserDefaults.standard
        let retention = defaults.integer(forKey: "CYTE_RETENTION")
        if retention == 0 {
            // retain forever
            log.info("Retain forever")
            return
        }
        let cutoff = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -(retention), to: Date())!
        log.info("Culling memories older than \(cutoff.formatted())")
        let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeFetch.predicate = NSPredicate(format: "start < %@", cutoff as CVarArg)
        do {
            let episodes = try PersistenceController.shared.container.viewContext.fetch(episodeFetch)
            for episode in episodes {
                log.info("Purging old episode: \(episode.start?.formatted())")
                delete(delete_episode: episode)
            }
        } catch {
            log.error("Failed to fetch episodes in retention")
        }
    }
    
    ///
    /// Push frame to encoder, run analysis (which will call us back with results for observation)
    ///
    @MainActor
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

    ///
    ///  Given a string representing visual observations for an instant,
    ///  diff against the last observations and when the change seems
    ///  non-additive, trigger a full text index with optional embedding.
    ///  When additive, save the delta only to save space and simplify search
    ///  duplication resolution
    ///
    @MainActor
    func observe(what: String) async {
        if episode == nil {
            fatalError("ERROR: NIL EPISODE")
        }
        let start = Date()
        let result: NSMutableArray = differ.diff_main(ofOldString: lastObservation, andNewString: what)!
        differ.diff_cleanupSemantic(result)
        // embed every 12sish
        var edits: [(Int, String)] = []
        var added: String = ""
        // if the edit removes the entirety of the lastObservation, then consider it a new context, and embed the current document total
        var total_match = 0
        for res in result {
            let edit: (Int, String) = (Int((res as! Diff).operation.rawValue) - 2,
                        ((res as! Diff).text ?? ""))
            edits.append(edit)
            if edit.0 == 1 {
                total_match += edit.1.count
            }
            if edit.0 == 0 {
                added += edit.1
            }
        }
        
        if total_match < 100 && lastObservation.count > 0 {
            // Delta must be non-zero to account for system wide text, e.g. date/time, battery percent
            print("Frames share little context (\(total_match)) - closing and embedding document")
            // Disable embedding until FAISS is integrated
            let embedding: [Double]? = nil//await Agent.shared.embed(input: lastObservation)
            if embedding != nil {
                insert(embedding:CyteEmbedding(time: start.timeIntervalSinceReferenceDate, text: what, vec: embedding!))
            }
        } else {
            print("Skip high delta \(total_match)")
        }
        
        let newItem = CyteInterval(from: start, to: Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: Memory.secondsBetweenFrames, to: start)!, episode: episode!, document: added)
        insert(interval: newItem)
        lastObservation = what
    }

    ///
    /// Deletes the provided episode including the underlying video file, and indexed interval data
    ///
    func delete(delete_episode: Episode) {
        if delete_episode.save {
            log.info("Saved episode from deletion")
            return
        }
        let intervals = intervalTable.filter(IntervalExpression.episodeStart == delete_episode.start!.timeIntervalSinceReferenceDate)
        let embeddings = embeddingTable.filter(Expression<Double>("episode_start") == delete_episode.start!.timeIntervalSinceReferenceDate)
        PersistenceController.shared.container.viewContext.delete(delete_episode)
        do {
            try intervalDb!.run(embeddings.delete())
            try intervalDb!.run(intervals.delete())
            try PersistenceController.shared.container.viewContext.save()
            try FileManager.default.removeItem(at: urlForEpisode(start: delete_episode.start, title: delete_episode.title))
        } catch {
        }
    }
    
    func search(term: String) -> [CyteInterval] {
        let intervalMatch: QueryType = term.count > 0 ? intervalTable.match("\(term)*").order(IntervalExpression.from).limit(100) : intervalTable.order(IntervalExpression.from).limit(100)
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
    
    func insert(embedding: CyteEmbedding) {
        do {
            // Generate an array of tuples with column names and values
            var columnsAndValues: [(String, Any)] = []
            for i in 1...Memory.embeddingSize {
                columnsAndValues.append(("d\(i)", embedding.vec[i-1]))
            }
            columnsAndValues.append(("episode_start", embedding.time))
            columnsAndValues.append(("fulltext", embedding.text))
            // Create a dictionary of column names and values
            var columnValues: [String: Any] = [:]
            for (column, value) in columnsAndValues {
                columnValues[column] = value
            }
            // Convert dictionary keys to expressions
            let expressions = columnValues.map { (key, value) -> Setter in
                if key == "fulltext" {
                    return Expression<String>(key) <- value as! String
                } else {
                    return Expression<Double>(key) <- value as! Double
                }
            }
            let insertQuery = embeddingTable.insert(expressions)
            try intervalDb!.run(insertQuery)
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
