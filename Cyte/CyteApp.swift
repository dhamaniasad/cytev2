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

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @StateObject var screenRecorder = ScreenRecorder()
    
    func setup() {
        appDelegate.mainApp = self
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
    
    var mainApp: CyteApp?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            // @fixme: remove this block once xib loading in notarized bundle is fixed
            NSApplication.shared.mainMenu?.removeItem(at: 5)
            NSApplication.shared.mainMenu?.removeItem(at: 4)
            NSApplication.shared.mainMenu?.removeItem(at: 3)
            NSApplication.shared.mainMenu?.removeItem(at: 2)
            NSApplication.shared.mainMenu?.removeItem(at: 1)
        }
        
        let nib = NSNib(nibNamed: NSNib.Name("MainMenu"), bundle: Bundle.main)
        nib?.instantiate(withOwner: NSApplication.shared, topLevelObjects: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }


    @objc private func sleepListener(_ aNotification: Notification) {
        print("listening to sleep")
        if aNotification.name == NSWorkspace.willSleepNotification {
            print("Going to sleep")
            if mainApp != nil {
                Task {
                    if await mainApp!.screenRecorder.isRunning {
                        await mainApp!.screenRecorder.stop()
                    }
                }
            }
        } else if aNotification.name == NSWorkspace.didWakeNotification {
            print("Woke up")
            if mainApp != nil {
                Task {
                    if await mainApp!.screenRecorder.canRecord {
                        await mainApp!.screenRecorder.start()
                    }
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Memory.shared.closeEpisode()
    }
}
