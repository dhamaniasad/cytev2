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
    @State var isShowing = false
    @State var apiDetails: String = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Tick to prevent recording the application")
                    .font(Font.subheadline)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Button(action: {
                    isShowing.toggle()
                }) {
                    Image(systemName: "macwindow.badge.plus")
                }
                .fileImporter(isPresented: $isShowing, allowedContentTypes: [.application], onCompletion: { result in
                    switch result {
                        case .success(let Fileurl):
                            let _ = Memory.shared.getOrCreateBundleExclusion(name: (Bundle(url: Fileurl)?.bundleIdentifier)!, excluded: true)
                            break
                        case .failure(let error):
                            print(error)
                    }
                })
            }
            .padding(EdgeInsets(top: 10.0, leading: 200.0, bottom: 10.0, trailing: 200.0))
            
            HStack {
                if LLM.shared.isSetup {
                    Text("OpenAI enabled")
                    
                } else {
                    TextField(
                        "OpenAI API Key",
                        text: $apiDetails
                    )
                    .onSubmit {
                        if apiDetails.contains("@") {
                            LLM.shared.setup(key: apiDetails)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 10.0, leading: 200.0, bottom: 10.0, trailing: 200.0))
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
            .padding(EdgeInsets(top: 10.0, leading: 200.0, bottom: 10.0, trailing: 200.0))
            
        }
    }
}
