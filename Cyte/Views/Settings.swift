//
//  Settings.swift
//  Cyte
//
//  Created by Shaun Narayan on 7/03/23.
//

import Foundation
import SwiftUI
import KeychainSwift

struct BundleView: View {
    
    @State var bundle: BundleExclusion
    
    var body: some View {
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

struct Settings: View {
    @FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \BundleExclusion.bundle, ascending: true)],
            animation: .default)
    private var bundles: FetchedResults<BundleExclusion>
    @State var isShowing = false
    @State var apiDetails: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Settings").font(.title)
                    .padding()
                Text("To enable GPT enter your API key").font(.title2)
                    .padding()
                HStack {
                    if Agent.shared.isSetup {
                        Text("OpenAI enabled")
                            .frame(width: 1000, height: 50)
                            .background(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                        Button(action: {
                            let keys = KeychainSwift()
                            let _ = keys.delete("CYTE_OPENAI_KEY")
                            Agent.shared.isSetup = false
                        }) {
                            Image(systemName: "multiply")
                        }
                        
                    } else {
                        TextField(
                            "OpenAI API Key",
                            text: $apiDetails
                        )
                        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                        .textFieldStyle(.plain)
                        .background(.white)
                        .font(.title)
                        .frame(width: 1000)
                        .onSubmit {
                            Agent.shared.setup(key: apiDetails)
                            apiDetails = ""
                        }
                    }
                }
                .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Select applications you wish to disable recording for")
                            .font(Font.title2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    Button(action: {
                        isShowing.toggle()
                    }) {
                        HStack {
                            Text("Add application")
                            Image(systemName: "plus")
                        }
                        .cornerRadius(10.0)
                        .foregroundColor(.gray)
                    }
                    .padding()
                    .buttonStyle(.plain)
                    .background(.white)
                    
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
                .padding()
            
                HStack {
                    List(Array(bundles.enumerated()), id: \.offset) { index, bundle in
                        if bundle.bundle != Bundle.main.bundleIdentifier && index % 2 == 0 {
                            BundleView(bundle: bundle)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .frame(width: 400)
                    List(Array(bundles.enumerated()), id: \.offset) { index, bundle in
                        if bundle.bundle != Bundle.main.bundleIdentifier && index % 2 == 1 {
                            BundleView(bundle: bundle)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .frame(width: 400)
                }
                .frame(height: ceil(CGFloat(bundles.count) / 2.0) * 40.0)
            }
        }
    }
}
