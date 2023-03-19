//
//  Index.swift
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

@MainActor
class Memory {
    static let shared = Memory()
    
    private var assetWriter : AVAssetWriter? = nil
    private var assetWriterInput : AVAssetWriterInput? = nil
    private var assetWriterAdaptor : AVAssetWriterInputPixelBufferAdaptor? = nil
    private var frameCount = 0
    private var currentContext : String = "Startup"
    private var currentStart: Date = Date()
    private var episode: Episode?
    private var subscriptions = Set<AnyCancellable>()
    private var concepts: Set<String> = Set()
    private var conceptTimes: Dictionary<String, DateInterval> = Dictionary()
    private var shouldTrackFileChanges: Bool = utsname.isAppleSilicon ? true : false
    
    init() {
        let unclosedFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        unclosedFetch.predicate = NSPredicate(format: "start == end")
        do {
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
        return recentFiles//Array(recentFiles.prefix(maxCount)) // change this number to show more or less files
    }
    
    //
    // Check the currently active app, if different since last check
    // then close the current episode and start a new one
    //
    func updateActiveContext() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "" }
        let context = front.bundleIdentifier ?? "Unnamed"
        if front.isActive && currentContext != context {
            if assetWriter != nil && assetWriterInput!.isReadyForMoreMediaData {
                closeEpisode()
            }
            currentContext = context
            let exclusion = Memory.shared.getOrCreateBundleExclusion(name: currentContext)
            if  assetWriter == nil && currentContext != Bundle.main.bundleIdentifier && exclusion.excluded == false {
                openEpisode()
            } else {
                print("Bypass exclusion context \(currentContext)")
            }
        }
        return currentContext
    }
    
    //
    // Sets up a stream to disk
    //
    func openEpisode() {
        Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                self.update()
            }
        }
        .store(in: &subscriptions)
        
        currentStart = Date()
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        //generate a file url to store the video. some_image.jpg becomes some_image.mov
        let outputMovieURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(front.localizedName!) \(currentStart.formatted(date: .abbreviated, time: .standard)).mov".replacingOccurrences(of: ":", with: "."))
        //create an assetwriter instance
        do {
            try assetWriter = AVAssetWriter(outputURL: outputMovieURL!, fileType: .mov)
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
        episode!.title = ""//assetWriter?.outputURL.deletingPathExtension().lastPathComponent
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
        
        for sub in subscriptions {
            sub.cancel()
        }
        subscriptions.removeAll()
                
        //close everything
        assetWriterInput!.markAsFinished()
        self.update(force_close: true)
        
        if frameCount < 7 || currentContext.starts(with:Bundle.main.bundleIdentifier!) {
            assetWriter!.cancelWriting()
            delete(delete_episode: episode!)
            Logger().info("Supressed small episode for \(self.currentContext)")
        } else {
            let ep = self.episode!
            assetWriter!.finishWriting {
                self.trackFileChanges(ep:ep)
            }
            
            self.episode!.title = self.assetWriter?.outputURL.deletingPathExtension().lastPathComponent
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
    
    func getOrCreateConcept(name: String) -> Concept {
        let conceptFetch : NSFetchRequest<Concept> = Concept.fetchRequest()
        conceptFetch.predicate = NSPredicate(format: "name == %@", name)
        do {
            let fetched = try PersistenceController.shared.container.viewContext.fetch(conceptFetch)
            if fetched.count > 0 {
                return fetched.first!
            }
        } catch {
            //failed, fallback to create
        }
        let concept = Concept(context: PersistenceController.shared.container.viewContext)
        concept.name = name
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return concept
    }
    
    func update(force_close: Bool = false) {
        // debounce concepts with a 5s tail to allow frame-frame overlap, reducing rate of outflow
        let current_time = Date()
        var closed_concepts = Set<String>()
        for concept in concepts {
            let this_concept_time = conceptTimes[concept]!
            let diff = current_time.timeIntervalSince(this_concept_time.end)
            if diff > 5.0 || force_close {
                // close the concept interval
                let concept_data = getOrCreateConcept(name: concept)
                let newItem = Interval(context: PersistenceController.shared.container.viewContext)
                newItem.from = this_concept_time.start
                newItem.to = this_concept_time.end
                newItem.concept = concept_data
                newItem.episode = episode

                do {
                    try PersistenceController.shared.container.viewContext.save()
                } catch {
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
                
                closed_concepts.insert(concept)
            }
        }
        for concept in closed_concepts {
            conceptTimes.removeValue(forKey: concept)
            concepts.remove(concept)
        }
    }

    func observe(what: String) {
        if !concepts.contains(what) {
            conceptTimes[what] = DateInterval(start: Date(), end: Date())
            concepts.insert(what)
        } else {
            conceptTimes[what]!.end = Date()
        }
    }

    func delete(delete_episode: Episode) {
        let intervalFetch : NSFetchRequest<Interval> = Interval.fetchRequest()
        intervalFetch.predicate = NSPredicate(format: "episode == %@", delete_episode)
        if let result = try? PersistenceController.shared.container.viewContext.fetch(intervalFetch) {
            for object in result {
                print("DELETED INTERVAL \(object.concept?.name)")
                PersistenceController.shared.container.viewContext.delete(object)
            }
        }
        PersistenceController.shared.container.viewContext.delete(delete_episode)
        do {
            try PersistenceController.shared.container.viewContext.save()
            try FileManager.default.removeItem(at:
                                            (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(delete_episode.title ?? "").mov"))!
            )
        } catch {
        }
    }
    
    func getOrCreateBundleExclusion(name: String) -> BundleExclusion {
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
        bundle.excluded = false
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
        }
        return bundle
    }
}
