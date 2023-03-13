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

    @State private var episodes: [Episode] = []
    @State private var intervals: [Interval] = []
    @State private var documentsForBundle: [Document] = []
    
    // The search terms currently active
    @State private var filter = ""
    @State private var highlightedBundle = ""
    @State private var showUsage = false
    
    @State private var chatModes = ["agent", "qa", "chat"]
    @State private var promptMode = "chat"
    
    @State private var bundleColors : Dictionary<String, Color> = ["": Color.gray]
    @State private var appIntervals : [AppInterval] = []
    
    // @todo make this responsive
    let feedColumnLayout = [
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60)
    ]
    
    // This is only because I'm not familiar with how Inverse relations work in CoreData, otherwise FetchRequest would automatically update the view. Please update if you can.
    @MainActor func refreshData() {
        if self.filter.count == 0 {
            let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeFetch.sortDescriptors = [NSSortDescriptor(key:"start", ascending: false)]
            if highlightedBundle.count != 0 {
                episodeFetch.predicate = NSPredicate(format: "bundle == %@", highlightedBundle)
            }
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
            intervalFetch.predicate = NSPredicate(format: "concept IN %@", concepts)
            intervalFetch.sortDescriptors = [NSSortDescriptor(key:"episode.start", ascending: false)]
            if highlightedBundle.count != 0 {
                intervalFetch.predicate = NSPredicate(format: "episode.bundle == %@", highlightedBundle)
            }
            episodes.removeAll()
            intervals.removeAll()
            if concepts.count < 5 {
                do {
                    intervals = try viewContext.fetch(intervalFetch)
                    for interval in intervals {
                        let ep_included: Episode? = episodes.first(where: { ep in
                            return ep.title == interval.episode!.title
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
                for doc in docs {
                    documentsForBundle.append(doc)
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
                    ForEach(episodes) { shape in
                        BarMark(
                            x: .value("Date", Calendar(identifier: Calendar.Identifier.iso8601).startOfDay(for: shape.start!)),
                            y: .value("Total Count", shape.end!.timeIntervalSince(shape.start!))
                        )
                        .opacity(highlightedBundle == shape.bundle! ? 0.7 : 1.0)
                        .foregroundStyle(by: .value("App", shape.bundle!))
                    }
                }
                .frame(height: 100)
                .chartLegend {
                }
                HStack {
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
                HStack {
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
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: 10, leading: 100, bottom: 10, trailing: 100))
        }
    }
    
    func intervalsForEpisode(episode: Episode) -> [Interval] {
        return intervals.filter { interval in
            return interval.episode!.start == episode.start
        }
    }
    
    var feed: some View {
        withAnimation {
            ScrollView {
                LazyVGrid(columns: feedColumnLayout, spacing: 20) {
                    ForEach(episodes) { episode in
                        EpisodeView(player: AVPlayer(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(episode.title ?? "").mov"))!), episode: episode, results: intervalsForEpisode(episode: episode), intervals: appIntervals)
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

    var body: some View {
        NavigationStack {
            VStack {
                if agent.chatLog.count > 0 {
                    ChatView()
                }
                ZStack {
                    let binding = Binding<String>(get: {
                        self.filter
                    }, set: {
                        self.filter = $0
                        self.refreshData()
                    })
                    HStack(alignment: .center) {
                        TextField(
                            "Search \(agent.isConnected ? "or chat " : "")your history",
                            text: binding
                        )
                        .frame(width: 950, height: 48)
                        .cornerRadius(5)
                        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                        .textFieldStyle(.plain)
                        .background(.white)
                        .cornerRadius(6.0)
                        .font(Font.title)
                        .prefersDefaultFocus(in: mainNamespace)
                        .onSubmit {
                            if agent.isConnected {
                                if agent.chatLog.count == 0 {
                                    agent.reset(promptStyle: promptMode)
                                }
                                agent.query(request: self.filter)
                                self.filter = ""
                            }
                        }
                        
                        HStack {
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
                            }
                            .frame(width: 40, height: 40)
                            .background(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                            .cornerRadius(5.0)
                            .buttonStyle(.plain)
                            
                            if agent.chatLog.count > 0 {
                                Picker("", selection: $promptMode) {
                                    ForEach(chatModes, id: \.self) {
                                        Text($0)
                                    }
                                }
                                .onChange(of: promptMode) { mode in agent.reset(promptStyle: promptMode) }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                                Button(action: {
                                    self.refreshData()
                                    agent.reset(promptStyle: promptMode)
                                }) {
                                    Image(systemName: "xmark.circle")
                                }
                                .padding()
                                .opacity(0.8)
                                .buttonStyle(.plain)
                            } else {
                                Button(action: {
                                    showUsage = !showUsage
                                }) {
                                    Image(systemName: "tray.and.arrow.down")
                                }
                                .padding()
                                .opacity(0.8)
                                .buttonStyle(.plain)
                                NavigationLink {
                                    Settings()
                                } label: {
                                    Image(systemName: "folder.badge.gearshape")
                                }
                                .opacity(0.8)
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .offset(x: -60.0)
                    }
                    
                }
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                
                if agent.chatLog.count == 0 {
                    if self.showUsage {
                        usage
                    }
                    Divider()
                    
                    feed
                } else {
                    
                }
            }
        }
        .padding(EdgeInsets(top: 0.0, leading: 30.0, bottom: 0.0, trailing: 30.0))
//        .background(
//            Rectangle().foregroundColor(Color(red: 194.0 / 255.0, green: 191.0 / 255.0, blue: 191.0 / 255.0 ))
//        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
