//
//  Settings.swift
//  Cyte
//
//  Created by Shaun Narayan on 7/03/23.
//

import Foundation
import SwiftUI

struct Settings: View {
    @FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \BundleExclusion.bundle, ascending: true)],
            animation: .default)
    private var bundles: FetchedResults<BundleExclusion>
    
    var body: some View {
        VStack {
            Text("Settings")
                .font(Font.title)
            Text("Tick to prevent recording the application")
                .font(Font.subheadline)
            List(bundles, id: \.self) { bundle in
                if bundle.bundle != Bundle.main.bundleIdentifier {
                    HStack {
                        let binding = Binding<Bool>(get: {
                            return bundle.excluded
                        }, set: {
                            if $0 {
                                bundle.excluded = true
                                do {
                                    try PersistenceController.shared.container.viewContext.save()
                                    // batch delete all episodes for bundle
                                    let intervalFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Interval")
                                    intervalFetchRequest.predicate = NSPredicate(format: "episode.bundle == %@", bundle.bundle!)
                                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: intervalFetchRequest)
                                    
                                    do {
                                        try PersistenceController.shared.container.viewContext.execute(deleteRequest)
                                    } catch {
                                    }
                                    
                                    let episodeFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Episode")
                                    episodeFetchRequest.predicate = NSPredicate(format: "bundle == %@", bundle.bundle!)
                                    let episodeDeleteRequest = NSBatchDeleteRequest(fetchRequest: episodeFetchRequest)
                                    
                                    do {
                                        try PersistenceController.shared.container.viewContext.execute(episodeDeleteRequest)
                                    } catch {
                                    }
                                } catch {
                                }
                            } else {
                                bundle.excluded = false
                                do {
                                    try PersistenceController.shared.container.viewContext.save()
                                } catch {
                                    
                                }
                            }
                            print($0)
                        })
                        Image(nsImage: getIcon(bundleID: bundle.bundle!)!)
                        Text(getApplicationNameFromBundleID(bundleID: bundle.bundle!)!)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(isOn: binding) {
                            
                        }
                    }
                }
            }
            .frame(width: 500, alignment: .center)
            
        }
    }
}
