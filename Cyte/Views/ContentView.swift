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
    @Namespace var mainNamespace
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var agent = Agent.shared
    
    @State private var dateRangeSelection = "Last 7 days"
    let dateRangeOptions = ["Last 24 hours", "Last 7 days", "Last 14 days", "Last 28 days"]

    @State private var episodes: [Episode] = []
    @State private var intervals: [CyteInterval] = []
    @State private var documentsForBundle: [Document] = []
    
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
    
    @State private var refreshTask: Task<(), Never>? = nil
    @State private var scrollViewID = UUID()
    
    let feedColumnLayout = [
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60)
    ]
    let documentsColumnLayout = [
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60)
    ]
    
    @MainActor func refreshData() {
        if refreshTask != nil && !refreshTask!.isCancelled {
            refreshTask!.cancel()
        }
        refreshTask = Task {
            // debounce to 600ms
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
                self.performRefreshData()
            } catch { }
        }
    }
    
    // This is only because I'm not familiar with how Inverse relations work in CoreData, otherwise FetchRequest would automatically update the view. Please update if you can
    @MainActor func performRefreshData() {
        scrollViewID = UUID()
        let ranges = [1, 7, 14, 28]
        startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -ranges[dateRangeOptions.firstIndex(of: dateRangeSelection)!], to: Date())!
        endDate = Date()
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
        
        refreshIcons()
        appIntervals = episodes.enumerated().map { (index, episode) in
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
                Chart {
                    ForEach(episodes.sorted {
                        return $0.bundle!.compare($1.bundle!).rawValue == 1
                    }) { shape in
                        BarMark(
                            x: .value("Date", Calendar(identifier: Calendar.Identifier.iso8601).startOfDay(for: shape.start!)),
                            y: .value("Total Count", shape.end!.timeIntervalSince(shape.start!))
                        )
                        .foregroundStyle(bundleColors[shape.bundle!] ?? .gray)
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
                                Text(getApplicationNameFromBundleID(bundleID: bundle)!)
                                    .foregroundColor(.black)
                            }
                            .contentShape(Rectangle())
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
        withAnimation {
            ScrollView {
                LazyVGrid(columns: feedColumnLayout, spacing: 20) {
                    if intervals.count == 0 {
                        ForEach(episodes.filter { ep in
                            return (ep.title ?? "").count > 0 && (ep.start != ep.end)
                        }) { episode in
                            EpisodeView(player: AVPlayer(url: urlForEpisode(start: episode.start, title: episode.title)), episode: episode, intervals: appIntervals, filter: filter)
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
                                    
                                }
                        }
                    }
                    else {
                        ForEach(intervals.filter { (interval: CyteInterval) in
                            return (interval.episode.title ?? "").count > 0
                        }) { (interval : CyteInterval) in
                            StaticEpisodeView(asset: AVAsset(url: urlForEpisode(start: interval.episode.start, title: interval.episode.title)), episode: interval.episode, result: interval, filter: filter, intervals: appIntervals)
                        }
                    }
                }
                .padding(.all)
            }
            .id(self.scrollViewID)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.refreshData()
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

    var body: some View {
        NavigationStack {
            VStack {
                if agent.chatLog.count > 0 {
                    ChatView()
                }
                VStack(alignment: .leading) {
                    ZStack {
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
                                    "Search \(agent.isConnected ? "or chat " : "")your history",
                                    text: binding
                                )
                                .frame(width: agent.chatLog.count == 0 ? 850 : nil, height: 48)
                                .cornerRadius(5)
                                .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                                .textFieldStyle(.plain)
                                .background(.white)
                                .border(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                                .cornerRadius(6.0)
                                .font(Font.title)
                                .prefersDefaultFocus(in: mainNamespace) // @fixme Causing AttributeGraph cycles
                                .onSubmit {
                                    Task {
                                        if agent.isConnected {
                                            Task {
                                                if agent.chatLog.count == 0 {
                                                    agent.reset()
                                                }
                                                await agent.query(request: self.filter)
                                                self.filter = ""
                                            }
                                        }
                                        refreshData()
                                    }
                                }
                                Button(action: {
                                    if agent.isConnected {
                                        Task {
                                            if agent.chatLog.count == 0 {
                                                agent.reset()
                                            }
                                            await agent.query(request: self.filter)
                                            self.filter = ""
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
                                .frame(width: 40, height: 40)
                                .buttonStyle(.plain)
                                .opacity(self.isHoveringSearch ? 0.8 : 1.0)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
                            }
                            
                            HStack {
                                if agent.chatLog.count == 0 {
                                    Button(action: {
                                        highlightedBundle = ""
                                        showUsage = !showUsage
                                        self.refreshData()
                                    }) {
                                        Image(systemName: "tray.and.arrow.down")
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
                                        Image(systemName: "star")
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
                                        Image(systemName: "folder.badge.gearshape")
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
                                    Spacer()
                                        .frame(maxWidth: .infinity)
                                    HStack {
                                        let calbinding = Binding<String>(get: {
                                            self.dateRangeSelection
                                        }, set: {
                                            self.dateRangeSelection = $0
                                            self.refreshData()
                                        })
                                        Image(systemName: "calendar")
                                        Picker("", selection: calbinding) {
                                            ForEach(dateRangeOptions, id: \.self) {
                                                Text($0)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    .padding()
                                    .foregroundColor(.gray)
                                    .background(.white)
                                    .border(.gray)
                                    .cornerRadius(4.0)
                                    .frame(width:190)
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
            Rectangle().foregroundColor(Color(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 250.0 / 255.0 ))
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
