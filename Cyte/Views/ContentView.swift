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

struct ToyShape: Identifiable {
    var color: String
    var type: String
    var count: Double
    var id = UUID()
}

struct ContentView: View {
    @Namespace var mainNamespace
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Episode.bundle, ascending: false)],
        animation: .default)
    private var episodesByBundle: FetchedResults<Episode>
    @State private var episodes: [Episode] = []
    
    // The search terms currently active
    @State private var filter = ""
    
    let feedColumnLayout = [
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60)
    ]
    
    func refreshData() {
        if self.filter.count == 0 {
            let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeFetch.sortDescriptors = [NSSortDescriptor(key:"start", ascending: false)]
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
                    TextField(
                        "Search your history",
                        text: binding
                    )
                    .frame(height: 48)
                    .cornerRadius(5)
                    .padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                    .font(Font.title)
                    .prefersDefaultFocus(in: mainNamespace)
                    
                }
                .padding(EdgeInsets(top: 10, leading: 100, bottom: 10, trailing: 100))
                ZStack {
                    Chart {
                        ForEach(episodesByBundle) { shape in
                            BarMark(
                                x: .value("Date", Calendar(identifier: Calendar.Identifier.iso8601).startOfDay(for: shape.start!)),
                                y: .value("Total Count", shape.end!.timeIntervalSince(shape.start!))
                            )
                            .foregroundStyle(by: .value("App", shape.bundle!))
                        }
                    }
                    .frame(height: 100)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { location in
                                    // Convert the gesture location to the coordiante space of the plot area.
                                    let origin = geometry[proxy.plotAreaFrame].origin
                                    let location = CGPoint(
                                        x: location.x - origin.x,
                                        y: location.y - origin.y
                                    )
                                    // Get the x (date) and y (price) value from the location.
//                                    let (date, price) = proxy.value(at: location, as: (String, Int).self)!
//                                    print("Location: \(date), \(price)")
//                                    self.refreshData()
                                }
                        }
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 100, bottom: 10, trailing: 100))
                
                ScrollView {
                    LazyVGrid(columns: feedColumnLayout, spacing: 20) {
                        ForEach(episodes) { episode in
                            VStack {
                                VideoPlayer(player: AVPlayer(url:  (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("\(episode.title ?? "").mov"))!))
                                NavigationLink {
                                    ZStack {
                                        VideoPlayer(player: AVPlayer(url:  (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("\(episode.title ?? "").mov"))!))
                                        
                                        // Create the custom overlay view
                                        VStack {
                                            Text("Custom Overlay")
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.blue)
                                                .cornerRadius(8)
                                        }
                                        .frame(width: 200, height: 100)
                                        .padding(.bottom, 20)
                                    }
                                } label: {
                                    Text(episode.title ?? "")
                                }
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
