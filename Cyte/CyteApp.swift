//
//  CyteApp.swift
//  Cyte
//
//  Created by Shaun Narayan on 27/02/23.
//

import SwiftUI

@main
struct CyteApp: App {
    let persistenceController = PersistenceController.shared

    @Environment(\.scenePhase) var scenePhase
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @StateObject var screenRecorder = ScreenRecorder()
    let appDelegate = AppDelegate()
    
    func setup() {
        NSApp.delegate = appDelegate
        Task {
            if await screenRecorder.canRecord {
                await screenRecorder.start()
            }
            HotkeyListener.register()
        }
    }
    
    func teardown() {
        Task {
            if await screenRecorder.canRecord {
                await screenRecorder.stop()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    self.setup()
                }
                .onDisappear {
                    self.teardown()
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        print("Active")
                    } else if newPhase == .inactive {
                        print("Inactive")
                    } else if newPhase == .background {
                        print("Background")
                    }
                }
        }
        MenuBarExtra(
                    "App Menu Bar Extra", systemImage: "star",
                    isInserted: $showMenuBarExtra)
                {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("Q")
                }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationWillTerminate(_ notification: Notification) {
        Memory.shared.closeEpisode()
    }
}
