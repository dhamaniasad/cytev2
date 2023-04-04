//
//  CyteApp.swift
//  Cyte
//
//  Created by Shaun Narayan on 27/02/23.
//

import SwiftUI
import XCGLogger
import AXSwift

@main
struct CyteApp: App {
    let persistenceController = PersistenceController.shared

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @StateObject var screenRecorder = ScreenRecorder.shared
    
    ///
    /// On first run, sets default prefernce values (90 day retention)
    /// On every run, starts the recorder and sets up hotkey listeners
    ///
    func setup() {
        appDelegate.mainApp = self
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "CYTE_RETENTION") == nil {
            defaults.set(90, forKey: "CYTE_RETENTION")
        }
        Task {
            if await screenRecorder.canRecord {
                await screenRecorder.start()
            }
            HotkeyListener.register()
        }
    }
    
    ///
    /// Stops the recorder which will in turn close any open episode and flush
    /// to disk.
    ///
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
        }
        .commands {
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
                        Button("Quit") { self.teardown(); NSApplication.shared.terminate(nil); }
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
        if !checkIsProcessTrusted(prompt: true) {
            log.error("Not trusted as an AX process; please authorize and re-launch")
        }
        let logUrl: URL = homeDirectory().appendingPathComponent("Log").appendingPathComponent("Cyte.log")
        do {
            try FileManager.default.createDirectory(at: logUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch { fatalError("Failed to create log dir") }
        let fileDest = AutoRotatingFileDestination(writeToFile: logUrl.path(percentEncoded: false))
        
        log.add(destination: fileDest)
        log.info("Cyte startup")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        
        
        do {
            let apps = Application.allForBundleID("com.google.Chrome")
            for app in apps {
                NSLog("finder: \(app)")
                for window in try app.windows()! {
                    let main = (try window.attribute(.main) as Bool?)
                    let url = (try window.attribute(.title) as String?)
                    print("\(url) ISMAIN: \(main)")
                }
            }
        } catch { }
        //(Incognito) | Private Browsing
        do {
            let apps = Application.allForBundleID("com.apple.Safari")
            for app in apps {
                NSLog("finder: \(app)")
                for window in try app.windows()! {
                    let main = (try window.attribute(.main) as Bool?)
                    let url = (try window.attribute(.title) as String?)
                    print("\(url) ISMAIN: \(main)")
                }
            }
        } catch { }
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
