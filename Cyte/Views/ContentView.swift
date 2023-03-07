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


func getIcon(bundleID: String) -> NSImage? {
    guard let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    
    guard FileManager.default.fileExists(atPath: path)
    else { return nil }
    
    return NSWorkspace.shared.icon(forFile: path)
}

func getApplicationNameFromBundleID(bundleID: String) -> String? {
    guard let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    guard let appBundle = Bundle(path: path),
          let executableName = appBundle.executableURL?.lastPathComponent else {
        return nil
    }
    return executableName
}

struct ContentView: View {
    @Namespace var mainNamespace
    @Environment(\.managedObjectContext) private var viewContext

    @State private var episodes: [Episode] = []
    @State private var documentsForBundle: [Document] = []
    
    // The search terms currently active
    @State private var filter = ""
    @State private var highlightedBundle = ""
    
    let feedColumnLayout = [
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60)
    ]
    
    @MainActor func refreshData() {
        if self.filter.count == 0 {
            let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeFetch.sortDescriptors = [NSSortDescriptor(key:"start", ascending: false)]
            if highlightedBundle.count != 0 {
                episodeFetch.predicate = NSPredicate(format: "bundle == %@", highlightedBundle)
            }
            do {
                episodes = try PersistenceController.shared.container.viewContext.fetch(episodeFetch)
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
            do {
                let intervals = try PersistenceController.shared.container.viewContext.fetch(intervalFetch)
                for interval in intervals {
                    episodes.append(interval.episode!)
                    print(interval.concept!.name!)
                    print(interval.episode!.start!)
                }
            } catch {
                
            }
        }
        // now that we have episodes, if a bundle is highlighted get the documents too
        documentsForBundle.removeAll()
        if highlightedBundle.count != 0 {
            let docFetch : NSFetchRequest<Document> = Document.fetchRequest()
            docFetch.predicate = NSPredicate(format: "episode.bundle == %@", highlightedBundle)
            do {
                let docs = try PersistenceController.shared.container.viewContext.fetch(docFetch)
                for doc in docs {
                    documentsForBundle.append(doc)
                }
            } catch {
                
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                ZStack {
                    let binding = Binding<String>(get: {
                        self.filter
                    }, set: {
                        self.filter = $0
                        self.refreshData()
                    })
                    HStack {
                        TextField(
                            "Search your history",
                            text: binding
                        )
                        .frame(height: 48)
                        .cornerRadius(5)
                        .padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        .font(Font.title)
                        .prefersDefaultFocus(in: mainNamespace)
                        
                        NavigationLink {
                            Settings()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    
                }
                .padding(EdgeInsets(top: 10, leading: 100, bottom: 10, trailing: 100))
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
                        ForEach(Set(episodes.map { $0.bundle ?? "shoplex.Cyte" }).sorted(by: <), id: \.self) { bundle in
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
                
                ScrollView {
                    LazyVGrid(columns: feedColumnLayout, spacing: 20) {
                        ForEach(episodes) { episode in
                            VStack {
                                VideoPlayer(player: AVPlayer(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(episode.title ?? "").mov"))!))
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
                                            Memory.shared.delete(episode: episode)
                                            self.refreshData()
                                        } label: {
                                            Label("Delete", systemImage: "xmark.bin")
                                        }
                                    
                                    }
                                NavigationLink {
                                    ZStack {
                                        Timeline(player: AVPlayer(url:  (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("\(episode.title ?? "").mov"))!), intervals: episodes.map { episode in
                                            return AppInterval(start: episode.start!, end: episode.end!, bundleId: episode.bundle!, title: episode.title!)
                                        }, displayInterval: (
                                            Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: -(Timeline.windowLengthInSeconds/2), to: episode.start!)!,
                                            Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: (Timeline.windowLengthInSeconds/2), to: episode.start!)!
//                                        ))
                                    }
                                } label: {
                                    HStack {
                                        VStack {
                                            Text(episode.title ?? "")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(episode.start!.formatted(date: .abbreviated, time: .standard) )
                                                .font(SwiftUI.Font.caption)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack {
                                            Image(systemName: episode.save ? "star.fill" : "star")
                                            Image(nsImage: getIcon(bundleID: episode.bundle!)!)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }.frame(height: 300)
                        }
                    }
                    .padding(.all)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    self.refreshData()
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
