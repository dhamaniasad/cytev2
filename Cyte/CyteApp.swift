//
//  CyteApp.swift
//  Cyte
//
//  Created by Shaun Narayan on 27/02/23.
//

import SwiftUI
import XCGLogger

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
        .commands {
            CommandGroup(replacing: .textEditing) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .printItem) { }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .systemServices) { }
            CommandGroup(replacing: .textFormatting) { }
            CommandGroup(replacing: .toolbar) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .sidebar) { }
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

let log = XCGLogger.default
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var mainApp: CyteApp?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let logUrl: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Cyte").appendingPathComponent("Log").appendingPathComponent("Cyte.log"))!
        do {
            try FileManager.default.createDirectory(at: logUrl.deletingLastPathComponent(), withIntermediateDirectories: false, attributes: nil)
        } catch { fatalError("Failed to log dir") }
        let fileDest = AutoRotatingFileDestination(writeToFile: logUrl.path(percentEncoded: false))
        
        log.add(destination: fileDest)
        log.info("Cyte startup")
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
