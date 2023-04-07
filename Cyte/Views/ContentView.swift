//
//  ContentView.swift
//  Cyte
//
//  The primary content is a search bar,
//  and a grid of videos with summarised metadata
//
//  Created by Shaun Narayan on 27/02/23.
//

import SwiftUI
import CoreData
import ScreenCaptureKit
import AVKit
import Charts
import Foundation
import Combine

extension Date {
    var dayOfYear: Int {
        return Calendar.current.ordinality(of: .day, in: .year, for: self)!
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var agent = Agent.shared
    @FocusState private var searchFocused: Bool
    
    @State private var episodes: [Episode] = []
    @State private var intervals: [CyteInterval] = []
    @State private var documentsForBundle: [Document] = []
    @State private var episodesLengthSum: Double = 0.0
    
    // The search terms currently active
    @State private var filter = ""
    @State private var highlightedBundle = ""
    @State private var showUsage = false
    @State private var showFaves = false
    
    @State private var startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -30, to: Date())!
    @State private var endDate = Date()
    
    @State private var bundleColors : Dictionary<String, Color> = ["": Color.gray]
    @State private var appIntervals : [AppInterval] = []
    
    // Hover states
    @State private var isHovering: Bool = false
    @State private var isHoveringSearch: Bool = false
    @State private var isHoveringUsage: Bool = false
    @State private var isHoveringSettings: Bool = false
    @State private var isHoveringFaves: Bool = false
    @State private var isHoveringFilter: Bool = false
    
    @State private var refreshTask: Task<(), Never>? = nil
    @State private var scrollViewID = UUID()
    @State private var isPresentingConfirm: Bool = false
    @State private var currentExport: AVAssetExportSession?
    
    @State private var progressID = UUID()
    @State private var timer: Timer?
    
    let feedColumnLayoutSmall = [
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50)
    ]
    
    let feedColumnLayout = [
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50)
    ]
    let feedColumnLayoutLarge = [
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50)
    ]
    let documentsColumnLayout = [
        GridItem(.fixed(190), spacing: 10, alignment: .topLeading),
        GridItem(.fixed(190), spacing: 10, alignment: .topLeading),
        GridItem(.fixed(190), spacing: 10, alignment: .topLeading),
        GridItem(.fixed(190), spacing: 10, alignment: .topLeading),
        GridItem(.fixed(190), spacing: 10, alignment: .topLeading),
        GridItem(.fixed(190), spacing: 10, alignment: .topLeading)
    ]
    
    @MainActor func refreshData() {
        if refreshTask != nil && !refreshTask!.isCancelled {
            refreshTask!.cancel()
        }
        if refreshTask == nil || refreshTask!.isCancelled {
            refreshTask = Task {
                // debounce to 400ms
                do {
                    try await Task.sleep(nanoseconds: 400_000_000)
                    self.performRefreshData()
                } catch { }
            }
        }
    }
    
    ///
    /// Runs queries according to updated UI selections
    /// This is only because I'm not familiar with how Inverse relations work in CoreData,
    /// otherwise FetchRequest would automatically update the view. Please update if you can
    ///
    @MainActor func performRefreshData() {
        scrollViewID = UUID()
        episodes.removeAll()
        intervals.removeAll()
        var _episodes: [Episode] = []
        
        if self.filter.count < 3 || self.filter.split(separator: " ").count > 5 {
            let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeFetch.sortDescriptors = [NSSortDescriptor(key:"start", ascending: false)]
            var pred = String("start >= %@ AND end <= %@")
            var args = [startDate as CVarArg, endDate as CVarArg]
            if highlightedBundle.count != 0 {
                pred += String("AND bundle == %@")
                args.append(highlightedBundle)
            }
            if showFaves {
                pred += String("AND save == true")
            }
            episodeFetch.predicate = NSPredicate(format: pred, argumentArray: args)
            do {
                _episodes = try viewContext.fetch(episodeFetch)
                intervals.removeAll()
            } catch {
                
            }
        } else {
            let potentials: [CyteInterval] = Memory.shared.search(term: self.filter, expanding: 2)
            withAnimation(.easeInOut(duration: 0.3)) {
                intervals = potentials.filter { (interval: CyteInterval) in
                    if showFaves && interval.episode.save != true {
                        return false
                    }
                    if highlightedBundle.count != 0  && interval.episode.bundle != highlightedBundle {
                        return false
                    }
                    let is_within = interval.episode.start ?? Date() >= startDate && interval.episode.end ?? Date() <= endDate
                    let ep_included: Episode? = episodes.first(where: { ep in
                        return ep.start == interval.episode.start
                    })
                    if ep_included == nil && is_within {
                        _episodes.append(interval.episode)
                    }
                    return is_within
                }
            }
        }
        
        for episode in _episodes {
            if !bundleColors.contains(where: { (bundleId, color) in
                return bundleId == episode.bundle
            }) {
                let color = getColor(bundleID: episode.bundle ?? Bundle.main.bundleIdentifier!)
                bundleColors[episode.bundle ?? Bundle.main.bundleIdentifier!] = Color(nsColor: color!)
            }
        }
        
        episodesLengthSum = 0.0
        appIntervals = _episodes.enumerated().map { (index, episode) in
            episodesLengthSum += (episode.end ?? Date()).timeIntervalSinceReferenceDate - (episode.start ?? Date()).timeIntervalSinceReferenceDate
            return AppInterval(start: episode.start ?? Date(), end: episode.end ?? Date(), bundleId: episode.bundle ?? "", title: episode.title ?? "", color: bundleColors[episode.bundle ?? ""] ?? Color.gray )
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            episodes = _episodes
        }
        // now that we have episodes, if a bundle is highlighted get the documents too
        // @todo break this out into its own component and use FetchRequest
        documentsForBundle.removeAll()
        if highlightedBundle.count != 0 {
            let docFetch : NSFetchRequest<Document> = Document.fetchRequest()
            docFetch.predicate = NSPredicate(format: "episode.bundle == %@", highlightedBundle)
            do {
                let docs = try viewContext.fetch(docFetch)
                var paths = Set<URL>()
                for doc in docs {
                    if !paths.contains(doc.path!) {
                        withAnimation(.easeIn(duration: 0.3)) {
                            documentsForBundle.append(doc)
                        }
                        paths.insert(doc.path!)
                    }
                }
            } catch {
                
            }
        }
    }
    
    func resetFilters() {
        filter = ""
        highlightedBundle = ""
        showUsage = false
        showFaves = false
        
        startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -30, to: Date())!
        endDate = Date()
    }
    
    var usage: some View {
        VStack {
            HStack(alignment: .center) {
                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .onChange(of: startDate, perform: { value in
                    refreshData()
                })
                .frame(width: 200, alignment: .leading)
                DatePicker(
                    " - ",
                    selection: $endDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .onChange(of: endDate, perform: { value in
                    refreshData()
                })
                .frame(width: 200, alignment: .leading)
                Spacer()
                Text("\(secondsToReadable(seconds: episodesLengthSum)) displayed")
                if episodesLengthSum < (60 * 60 * 40) && (currentExport == nil || currentExport!.progress >= 1.0) {
                    Button(action: {
                        Task {
                            currentExport = await makeTimelapse(episodes: episodes.reversed())
                        }
                    }) {
                        Image(systemName: "timelapse")
                    }
                    .buttonStyle(.plain)
                    .onHover(perform: { hovering in
                        self.isHovering = hovering
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    })
                }
                Button(action: {
                    isPresentingConfirm = true
                }) {
                    Image(systemName: "folder.badge.minus")
                }
                .buttonStyle(.plain)
                .onHover(perform: { hovering in
                    self.isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                })
                .confirmationDialog("This action cannot be undone. Are you sure?",
                 isPresented: $isPresentingConfirm) {
                    Button("Delete all results", role: .destructive) {
                         for episode in episodes {
                             Memory.shared.delete(delete_episode: episode)
                         }
                         refreshData()
                    }
                }
            }
            
            if (Set(episodes.map { $0.start?.dayOfYear }).count > 5) {
                Chart {
                    ForEach(episodes.sorted {
                        return ($0.bundle ?? "").compare($1.bundle ?? "").rawValue == 1
                    }) { shape in
                        BarMark(
                            x: .value("Date", Calendar(identifier: Calendar.Identifier.iso8601).startOfDay(for: shape.start ?? Date())),
                            y: .value("Total Count", (shape.end ?? Date()).timeIntervalSince(shape.start ?? Date()))
                        )
                        .foregroundStyle(bundleColors[shape.bundle ?? ""] ?? .gray)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .frame(height: 100)
                .chartLegend {
                }
            }
            
            HStack {
                LazyVGrid(columns: documentsColumnLayout, spacing: 20) {
                    ForEach(Set(episodes.map { $0.bundle ?? Bundle.main.bundleIdentifier! }).sorted(by: <), id: \.self) { bundle in
                        HStack {
                            Image(nsImage: getIcon(bundleID: bundle)!)
                            Text(getApplicationNameFromBundleID(bundleID: bundle) ?? "")
                                .foregroundColor(.black)
                        }
                        .contentShape(Rectangle())
                        .onHover(perform: { hovering in
                            self.isHoveringFilter = hovering
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        })
                        .onTapGesture { gesture in
                            if highlightedBundle.count == 0 {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    highlightedBundle = bundle
                                }
                            } else {
                                highlightedBundle = ""
                            }
                            self.refreshData()
                        }
                    }
                }
            }
            HStack {
                LazyVGrid(columns: documentsColumnLayout, spacing: 20) {
                    ForEach(documentsForBundle) { doc in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: String(doc.path!.absoluteString.dropFirst(7))))
                            Text(doc.path!.lastPathComponent)
                                .foregroundColor(.black)
                        }
                        .onHover(perform: { hovering in
                            self.isHoveringFilter = hovering
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        })
                        .onTapGesture { gesture in
                            // @todo should really open with currently highlighted bundle
                            NSWorkspace.shared.open(doc.path!)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
    }
    
    var feed: some View {
        GeometryReader { metrics in
            if episodes.count == 0 && intervals.count == 0 {
                Text("No results found. Update your search, or record some more activity").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollViewReader { value in
                    ScrollView {
                        LazyVGrid(columns: (metrics.size.width > 1500 && utsname.isAppleSilicon) ? feedColumnLayoutLarge : (metrics.size.width > 1200 ? feedColumnLayout : feedColumnLayoutSmall), spacing: 20) {
                            if intervals.count == 0 {
                                ForEach(episodes.filter { ep in
                                    return (ep.title ?? "").count > 0 && (ep.start != ep.end)
                                }) { episode in
                                    EpisodeView(player: AVPlayer(url: urlForEpisode(start: episode.start, title: episode.title)), episode: episode, intervals: appIntervals, filter: filter, selected: false)
                                        .frame(width: 360, height: 260)
                                        .contextMenu {
                                            Button {
                                                Memory.shared.delete(delete_episode: episode)
                                                self.refreshData()
                                            } label: {
                                                Label("Delete", systemImage: "xmark.bin")
                                            }
                                            Button {
                                                revealEpisode(episode: episode)
                                            } label: {
                                                Label("Reveal in Finder", systemImage: "questionmark.folder")
                                            }
                                        }
                                        .id(episode.start)
                                }
                            }
                            else {
                                ForEach(intervals.filter { (interval: CyteInterval) in
                                    return (interval.episode.title ?? "").count > 0
                                }) { (interval : CyteInterval) in
                                    StaticEpisodeView(asset: AVAsset(url: urlForEpisode(start: interval.episode.start, title: interval.episode.title)), episode: interval.episode, result: interval, filter: filter, intervals: appIntervals, selected: false)
                                        .id(interval.from)
                                }
                            }
                        }
                        .padding(.all)
                        .animation(.easeInOut(duration: 0.3), value: episodes)
                        .animation(.easeInOut(duration: 0.3), value: intervals)
                    }
                    .id(self.scrollViewID)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if !self.showUsage {
                                self.resetFilters()
                                endDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: 2, to: Date())!
                            }
                            self.refreshData()
                        }
                    }
                }
            }
        }
    }
    
    func runSearch() {
        if Agent.shared.isSetup && self.filter.hasSuffix("?") {
            Task {
                if refreshTask != nil && !refreshTask!.isCancelled {
                    refreshTask!.cancel()
                }
                if !self.filter.hasPrefix("chat ") {
                    agent.reset()
                }
                let what = self.filter
                self.filter = ""
                await agent.query(request: what, over: intervals)
            }
        } else {
            refreshData()
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if agent.chatLog.count > 0 {
                    GeometryReader { metrics in
                        ChatView(intervals: appIntervals, displaySize: metrics.size)
                    }
                }
                VStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        let binding = Binding<String>(get: {
                            self.filter
                        }, set: {
                            self.filter = $0
                        })
                        HStack(alignment: .center) {
                            ZStack(alignment:.trailing) {
                                TextField(
                                    "Search \(Agent.shared.isSetup ? "or chat " : "")your history",
                                    text: binding
                                )
                                .frame(width: agent.chatLog.count == 0 ? 650 : nil, height: 48)
                                .cornerRadius(5)
                                .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                                .textFieldStyle(.plain)
                                .background(.white)
                                .cornerRadius(10.0)
                                .font(Font.title)
                                .foregroundColor(Color(red: 107.0 / 255.0, green: 107.0 / 255.0, blue: 107.0 / 255.0))
                                .focused($searchFocused)
                                .onSubmit {
                                    self.runSearch()
                                }
                                Button(action: {
                                    self.runSearch()
                                }) {
                                    Image(systemName: "paperplane")
                                        .onHover(perform: { hovering in
                                            self.isHoveringSearch = hovering
                                            if hovering {
                                                NSCursor.pointingHand.set()
                                            } else {
                                                NSCursor.arrow.set()
                                            }
                                        })
                                        .foregroundColor(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                                }
                                .frame(width: 60, height: 60)
                                .buttonStyle(.plain)
                                .opacity(self.isHoveringSearch ? 0.8 : 1.0)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
                            }
                            .frame(alignment: .leading)
                            
                            HStack {
                                if agent.chatLog.count == 0 {
                                    Button(action: {
                                        let showing = self.showUsage
                                        if showing {
                                            self.resetFilters()
                                        }
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            self.showUsage = !showing
                                        }
                                        self.refreshData()
                                    }) {
                                        Image(systemName: showUsage ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    }
                                    .padding()
                                    .opacity(0.8)
                                    .buttonStyle(.plain)
                                    .opacity(isHoveringUsage ? 0.8 : 1.0)
                                    .onHover(perform: { hovering in
                                        self.isHoveringUsage = hovering
                                        if hovering {
                                            NSCursor.pointingHand.set()
                                        } else {
                                            NSCursor.arrow.set()
                                        }
                                    })
                                    
                                    Button(action: {
                                        highlightedBundle = ""
                                        showFaves = !showFaves
                                        self.refreshData()
                                    }) {
                                        Image(systemName: showFaves ? "star.fill": "star")
                                    }
                                    .opacity(0.8)
                                    .buttonStyle(.plain)
                                    .padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 0.0))
                                    .opacity(isHoveringFaves ? 0.8 : 1.0)
                                    .onHover(perform: { hovering in
                                        self.isHoveringFaves = hovering
                                        if hovering {
                                            NSCursor.pointingHand.set()
                                        } else {
                                            NSCursor.arrow.set()
                                        }
                                    })
                                    
                                    NavigationLink {
                                        Settings()
                                    } label: {
                                        Image(systemName: "gearshape")
                                    }
                                    .padding()
                                    .opacity(isHoveringSettings ? 0.8 : 1.0)
                                    .buttonStyle(.plain)
                                    .onHover(perform: { hovering in
                                        self.isHoveringSettings = hovering
                                        if hovering {
                                            NSCursor.pointingHand.set()
                                        } else {
                                            NSCursor.arrow.set()
                                        }
                                    })
                                    
                                    Button(action: {
                                        resetFilters()
                                        self.refreshData()
                                    }) {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.plain)
                                    .transformEffect(CGAffineTransformMakeScale(-1, 1))
                                    .padding(EdgeInsets(top: 0.0, leading: 10.0, bottom: 0.0, trailing: 0.0))
                                    .onHover(perform: { hovering in
                                        self.isHovering = hovering
                                        if hovering {
                                            NSCursor.pointingHand.set()
                                        } else {
                                            NSCursor.arrow.set()
                                        }
                                    })
                                    Spacer()
                                    if currentExport != nil && currentExport!.progress < 1.0 {
                                        HStack {
                                            ProgressView("Exporting…", value: currentExport!.progress, total: 1.0)
                                                .frame(width: 250)
                                            Button(action: {
                                                currentExport?.cancelExport()
                                                currentExport = nil
                                            }) {
                                                Image(systemName: "stop.circle")
                                            }
                                            .id(progressID)
                                            .onAppear {
                                                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                                                    progressID = UUID()
                                                })
                                            }
                                            .onDisappear {
                                                timer?.invalidate()
                                            }
                                            .buttonStyle(.plain)
                                            .onHover(perform: { hovering in
                                                self.isHovering = hovering
                                                if hovering {
                                                    NSCursor.pointingHand.set()
                                                } else {
                                                    NSCursor.arrow.set()
                                                }
                                            })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: 10, leading: agent.chatLog.count == 0 ? 0 : 210, bottom: 10, trailing: agent.chatLog.count == 0 ? 0 : 210))
                
                if agent.chatLog.count == 0 {
                    if self.showUsage {
                        usage
                    }
                    feed
                } else {
                    
                }
            }
        }
        .onAppear {
            self.refreshData()
        }
        .padding(EdgeInsets(top: 0.0, leading: 30.0, bottom: 0.0, trailing: 30.0))
        .background(
            Rectangle().foregroundColor(Color(red: 240.0 / 255.0, green: 240.0 / 255.0, blue: 240.0 / 255.0 ))
        )
    }
}

