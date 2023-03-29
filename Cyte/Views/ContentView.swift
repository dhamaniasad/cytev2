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
    @State private var isHoveringSearch: Bool = false
    @State private var isHoveringUsage: Bool = false
    @State private var isHoveringSettings: Bool = false
    @State private var isHoveringFaves: Bool = false
    @State private var isHoveringFilter: Bool = false
    
    @State private var refreshTask: Task<(), Never>? = nil
    @State private var scrollViewID = UUID()
    @State var selectedIndex = -1
    
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
        selectedIndex = -1
        episodes.removeAll()
        intervals.removeAll()
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
                episodes = try viewContext.fetch(episodeFetch)
                intervals.removeAll()
            } catch {
                
            }
        } else {
            let potentials: [CyteInterval] = Memory.shared.search(term: self.filter)
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
                    episodes.append(interval.episode)
                }
                return is_within
            }
        }
//        if episodes.count > 0 {
//            agent.chatLog.append(("user", "", "hi"))
//            agent.chatLog.append(("bot", "gpt4", "hello"))
//            agent.chatSources.append([])
//            agent.chatSources.append(episodes)
//        }
        
        refreshIcons()
        episodesLengthSum = 0.0
        appIntervals = episodes.enumerated().map { (index, episode) in
            episodesLengthSum += (episode.end ?? Date()).timeIntervalSinceReferenceDate - (episode.start ?? Date()).timeIntervalSinceReferenceDate
            return AppInterval(start: episode.start ?? Date(), end: episode.end ?? Date(), bundleId: episode.bundle ?? "", title: episode.title ?? "", color: bundleColors[episode.bundle ?? ""]! )
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
                        documentsForBundle.append(doc)
                        paths.insert(doc.path!)
                    }
                }
            } catch {
                
            }
        }
    }
    
    func refreshIcons() {
        for episode in episodes {
            if !bundleColors.contains(where: { (bundleId, color) in
                return bundleId == episode.bundle
            }) {
                let color = getColor(bundleID: episode.bundle ?? Bundle.main.bundleIdentifier!)
                bundleColors[episode.bundle ?? Bundle.main.bundleIdentifier!] = Color(nsColor: color!)
            }
        }
    }
    
    func intervalForEpisode(episode: Episode) -> (Date, Date) {
        // @fixme Adding a small offset to ensure interval matching passes
        return (
            Date(timeIntervalSinceReferenceDate: (episode.start ?? Date()).timeIntervalSinceReferenceDate + 0.01-(Double(Timeline.windowLengthInSeconds)/2.0)),
            Date(timeIntervalSinceReferenceDate: (episode.start ?? Date()).timeIntervalSinceReferenceDate + 0.01+(Double(Timeline.windowLengthInSeconds)/2.0))
        )
    }
    
    var usage: some View {
        withAnimation {
            VStack {
                HStack(alignment: .center) {
                    DatePicker(
                        "",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .frame(width: 200, alignment: .leading)
                    DatePicker(
                        " - ",
                        selection: $endDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .frame(width: 200, alignment: .leading)
                    Spacer()
                    Text("\(secondsToReadable(seconds: episodesLengthSum)) displayed")
                }
                
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
                .frame(height: 100)
                .chartLegend {
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
                                    highlightedBundle = bundle
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
    }
    
    var feed: some View {
        GeometryReader { metrics in
            withAnimation {
                ScrollViewReader { value in
                    
                    Group {
                        Button(action: { move(amount:-1); value.scrollTo(filter.count > 0 ? intervals[selectedIndex].from : episodes[selectedIndex].start); }) {}
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        Button(action: { move(amount:1); value.scrollTo(filter.count > 0 ? intervals[selectedIndex].from : episodes[selectedIndex].start); }) {}
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        Button(action: { searchFocused = true; selectedIndex = -1; print(metrics.size); }) {}
                            .keyboardShortcut(.escape, modifiers: [])
                    }.frame(maxWidth: 0, maxHeight: 0).opacity(0)
                    ScrollView {
                        
                        LazyVGrid(columns: (metrics.size.width > 1500 && utsname.isAppleSilicon) ? feedColumnLayoutLarge : (metrics.size.width > 1200 ? feedColumnLayout : feedColumnLayoutSmall), spacing: 20) {
                            if intervals.count == 0 {
                                ForEach(episodes.filter { ep in
                                    return (ep.title ?? "").count > 0 && (ep.start != ep.end)
                                }) { episode in
                                    EpisodeView(player: AVPlayer(url: urlForEpisode(start: episode.start, title: episode.title)), episode: episode, intervals: appIntervals, filter: filter, selected: selectedIndex >= 0 && episode.start == episodes[selectedIndex].start)
                                        .frame(width: 360, height: 260)
                                        .contextMenu {
                                            Button {
                                                episode.save = !episode.save
                                                do {
                                                    try PersistenceController.shared.container.viewContext.save()
                                                    self.refreshData()
                                                } catch {
                                                }
                                            } label: {
                                                Label(episode.save ? "Remove from Favorites" : "Add to Favorites", systemImage: "heart")
                                            }
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
                                            Button {
                                                let _ = makeTimelapse(episodes: episodes)
                                            } label: {
                                                Label("Export results as timelaspse", systemImage: "timelapse")
                                            }
                                            Button {
                                                for i in 0...episodes.count {
                                                    Memory.shared.delete(delete_episode: episodes[i])
                                                }
                                                refreshData()
                                            } label: {
                                                Label("DELETE ALL DISPLAYED RESULTS", systemImage: "exclamationmark.triangle")
                                            }
                                        }
                                        .id(episode.start)
                                }
                            }
                            else {
                                ForEach(intervals.filter { (interval: CyteInterval) in
                                    return (interval.episode.title ?? "").count > 0
                                }) { (interval : CyteInterval) in
                                    StaticEpisodeView(asset: AVAsset(url: urlForEpisode(start: interval.episode.start, title: interval.episode.title)), episode: interval.episode, result: interval, filter: filter, intervals: appIntervals, selected: selectedIndex >= 0 && interval.from == intervals[selectedIndex].from)
                                        .id(interval.from)
                                }
                            }
                        }
                        .padding(.all)
                    }
                    .id(self.scrollViewID)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if !self.showUsage {
                                endDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: 2, to: Date())!
                            }
                            self.refreshData()
                        }
                    }
                }
            }
        }
    }
    
    func getDateRange(start: Bool) -> ClosedRange<Date> {
        if start {
            return (episodes.last?.start ?? Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -30, to: Date())!) ... (endDate)
        }
        return (startDate) ... (episodes.first?.end ?? Date())
        
    }
    
    func move(amount: Int) {
        searchFocused = false
        let total_displayed = filter.count == 0 ? episodes.count : intervals.count
        if (selectedIndex + amount) >= 0 && (selectedIndex + amount) < total_displayed {
            selectedIndex += amount
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
                            self.intervals.removeAll()
                            self.refreshData()
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
                                    Task {
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
                                                await agent.query(request: what)
                                            }
                                        }
                                        refreshData()
                                    }
                                }
                                Button(action: {
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
                                            await agent.query(request: what)
                                        }
                                    }
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
                                        highlightedBundle = ""
                                        showUsage = !showUsage
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
                                }
                                if agent.chatLog.count == 0 {
                                    Spacer()
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
        .padding(EdgeInsets(top: 0.0, leading: 30.0, bottom: 0.0, trailing: 30.0))
        .background(
            Rectangle().foregroundColor(Color(red: 240.0 / 255.0, green: 240.0 / 255.0, blue: 240.0 / 255.0 ))
        )
    }
}

