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
//    @Namespace var mainNamespace
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var agent = Agent.shared

    @State private var episodes: [Episode] = []
    @State private var intervals: [Interval] = []
    @State private var documentsForBundle: [Document] = []
    
    // The search terms currently active
    @State private var filter = ""
    @State private var highlightedBundle = ""
    @State private var showUsage = false
    @State private var showFaves = false
    
    @State private var startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -30, to: Date())!
    @State private var endDate = Date()
    
    @State private var chatModes = ["agent", "qa", "chat"]
    @State private var promptMode = "qa"
    
    @State private var bundleColors : Dictionary<String, Color> = ["": Color.gray]
    @State private var appIntervals : [AppInterval] = []
    
    // Hover states
    @State private var isHoveringSearch: Bool = false
    @State private var isHoveringRetrySearch: Bool = false
    @State private var isHoveringUsage: Bool = false
    @State private var isHoveringSettings: Bool = false
    @State private var isHoveringFaves: Bool = false
    
    @State private var lastRefresh: Date = Date()
    
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
    
    // This is only because I'm not familiar with how Inverse relations work in CoreData, otherwise FetchRequest would automatically update the view. Please update if you can
    @MainActor func refreshData() {
        if (Date().timeIntervalSinceReferenceDate - lastRefresh.timeIntervalSinceReferenceDate) < 0.5 {
            //@fixme poor mans debounce because it will miss the trailing edge, still deciding best way to structure
            return
        }
        lastRefresh = Date()
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
            let concept_strs = self.filter.split(separator: " ")
            var concepts : [Concept] = []
            for concept in concept_strs {
                concepts.append(Memory.shared.getOrCreateConcept(name: concept.lowercased()))
            }
            let intervalFetch : NSFetchRequest<Interval> = Interval.fetchRequest()
            intervalFetch.sortDescriptors = [NSSortDescriptor(key:"episode.start", ascending: false)]
            
            var pred = String("episode.start >= %@ AND episode.end <= %@ AND concept IN %@")
            var args = [startDate as CVarArg, endDate as CVarArg, concepts]
            if highlightedBundle.count != 0 {
                pred += String("AND episode.bundle == %@")
                args.append(highlightedBundle)
            }
            if showFaves {
                pred += String("AND episode.save == true")
            }
            
            intervalFetch.predicate = NSPredicate(format: pred, argumentArray: args)
            
            if concepts.count < 5 {
                do {
                    let potentials = try viewContext.fetch(intervalFetch)
                    for interval in potentials {
                        intervals.append(interval)
                        let ep_included: Episode? = episodes.first(where: { ep in
                            return ep.start == interval.episode!.start
                        })
                        if ep_included == nil {
                            episodes.append(interval.episode!)
                        }
                    }
                } catch {
                    
                }
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
    
    func intervalsForEpisode(episode: Episode) -> [Interval] {
        let ints = intervals.filter { interval in
            let match = interval.from!.timeIntervalSinceReferenceDate >= episode.start!.timeIntervalSinceReferenceDate &&
            interval.from!.timeIntervalSinceReferenceDate <= episode.end!.timeIntervalSinceReferenceDate
            return match
        }
        return ints
    }
    
    var feed: some View {
        withAnimation {
            ScrollView {
                LazyVGrid(columns: feedColumnLayout, spacing: 20) {
                    if filter.count < 3 {
                        ForEach(episodes.filter { ep in
                            return (ep.title ?? "").count > 0
                        }) { episode in
                            EpisodeView(player: AVPlayer(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(episode.title ?? "").mov"))!), episode: episode, results: intervalsForEpisode(episode: episode), intervals: appIntervals)
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
                    } else {
                        ForEach(intervals.filter { interval in
                            return interval.episode != nil && (interval.episode!.title ?? "").count > 0
                        }) { interval in
                            StaticEpisodeView(asset: AVAsset(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(interval.episode!.title ?? "").mov"))!), episode: interval.episode!, result: interval, intervals: appIntervals)
                        }
                    }
                }
                .padding(.all)
            }
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
//                           self.refreshData()
                        })
                        HStack(alignment: .center) {
                            ZStack(alignment:.trailing) {
                                TextField(
                                    "Search \(agent.isConnected ? "or chat " : "")your history",
                                    text: binding
                                )
                                .frame(width: agent.chatLog.count == 0 ? 950 : nil, height: 48)
                                .cornerRadius(5)
                                .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                                .textFieldStyle(.plain)
                                .background(.white)
                                .cornerRadius(6.0)
                                .font(Font.title)
//                                .prefersDefaultFocus(in: mainNamespace) // @fixme Causing AttributeGraph cycles
                                .onSubmit {
                                    Task {
                                        if agent.isConnected {
                                            if agent.chatLog.count == 0 {
                                                agent.reset(promptStyle: promptMode)
                                            }
                                            agent.query(request: self.filter)
                                            self.filter = ""
                                        }
                                        refreshData()
                                    }
                                }
                                Button(action: {
                                    if agent.isConnected {
                                        if agent.chatLog.count == 0 {
                                            agent.reset(promptStyle: promptMode)
                                        }
                                        agent.query(request: self.filter)
                                        self.filter = ""
                                    }
                                }) {
                                    Image(systemName: "paperplane")
                                        .frame(width: 50, height: 50)
                                        .colorInvert()
                                        .onHover(perform: { hovering in
                                            self.isHoveringSearch = hovering
                                            if hovering {
                                                NSCursor.pointingHand.set()
                                            } else {
                                                NSCursor.arrow.set()
                                            }
                                        })
                                }
                                .frame(width: 40, height: 40)
                                .background(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                                .cornerRadius(5.0)
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
                                }
                                if agent.chatLog.count == 0 {
                                    Spacer()
                                }
                            }
                        }
                    }
                    if agent.chatLog.count > 0 {
                        HStack {
                            Button(action: {
                                self.refreshData()
                                agent.reset(promptStyle: promptMode)
                            }) {
                                Text("Back to Search")
                                    .underline()
                            }
                            .onHover(perform: { hovering in
                                self.isHoveringRetrySearch = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
                            .opacity(isHoveringRetrySearch ? 0.8 : 1.0)
                            .foregroundColor(.gray)
                            .buttonStyle(.plain)
                        }
                        .padding()
                    }
                }
                .padding(EdgeInsets(top: 10, leading: agent.chatLog.count == 0 ? 0 : 210, bottom: 10, trailing: agent.chatLog.count == 0 ? 0 : 210))
                
                if agent.chatLog.count == 0 {
                    let bindingStart = Binding<Date>(get: {
                        self.startDate
                    }, set: {
                        self.startDate = $0
                        self.refreshData()
                    })
                    let bindingEnd = Binding<Date>(get: {
                        self.endDate
                    }, set: {
                        self.endDate = $0
                        self.refreshData()
                    })
                    HStack(alignment: .center) {
                        DatePicker(
                            "From",
                            selection: bindingStart,
//                            in: getDateRange(start:true),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .frame(width: 200)
                        DatePicker(
                            "Until",
                            selection: bindingEnd,
//                            in: getDateRange(start:false),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .frame(width: 200)
                        Spacer()
                    }
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
            Rectangle().foregroundColor(Color(red: 233.0 / 255.0, green: 233.0 / 255.0, blue: 233.0 / 255.0 ))
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
