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
                .contentShape(Rectangle())
                .onAppear {
                    self.setup()
                }
                .onDisappear {
                    self.teardown()
                }
        }
        MenuBarExtra(
                    "App Menu Bar Extra", image: "LogoIcon",
                    isInserted: $showMenuBarExtra)
                {
                    VStack {
                        HStack {
                            Button(screenRecorder.isRunning ? "Pause" : "Record") {
                                
                                Task {
                                    if screenRecorder.isRunning {
                                        await screenRecorder.stop()
                                    }
                                    else if await screenRecorder.canRecord {
                                        await screenRecorder.start()
                                    }
                                }
                            }
                            .keyboardShortcut("R")
                        }
                        Divider()
                        Button("Quit") { NSApplication.shared.terminate(nil) }
                            .keyboardShortcut("Q")
                    }
                    .frame(width: 200)
                }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationWillTerminate(_ notification: Notification) {
        Memory.shared.closeEpisode()
    }
}
