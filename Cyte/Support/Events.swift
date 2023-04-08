//
//  Events.swift
//  Cyte
//
//  From stackoverflow
//

import Foundation
import Carbon
import AppKit
import SwiftUI

extension NSImage {
    ///
    /// This is used as a background color for contexts related to an app, like chart axis etc
    ///
    var averageColor: NSColor? {
        if self.tiffRepresentation == nil { return nil }
        guard let inputImage = CIImage(data: self.tiffRepresentation!) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        return NSColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
}

class BundleCache: ObservableObject {
    @Published var bundleImageCache: [String: NSImage] = [:]
    @Published var bundleColorCache : Dictionary<String, NSColor> = ["": NSColor.gray]
    
    func getColor(bundleID: String) -> NSColor? {
        if bundleColorCache[bundleID] != nil {
            return bundleColorCache[bundleID]!
        }
        return NSColor.gray
    }
    
    func getIcon(bundleID: String) -> NSImage {
        if bundleImageCache[bundleID] != nil {
            return bundleImageCache[bundleID]!
        }
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false)
        else {
            URLSession.shared.dataTask(with: FavIcon(bundleID)[.m]) { (data, response, error) in
                guard let imageData = data else { return }
                
                DispatchQueue.main.async {
                    self.bundleImageCache[bundleID] = NSImage(data: imageData)
                    self.bundleColorCache[bundleID] = self.bundleImageCache[bundleID]!.averageColor
                }
            }.resume()
            return NSImage()
        }
        
        guard FileManager.default.fileExists(atPath: path)
        else { return NSImage() }
        
        let icon = NSWorkspace.shared.icon(forFile: path)
        DispatchQueue.main.async { [self] in
            bundleImageCache[bundleID] = icon
            bundleColorCache[bundleID] = icon.averageColor
        }
        return icon
    }
}
func getApplicationNameFromBundleID(bundleID: String) -> String? {
    guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false)
    else { return bundleID }
    guard let appBundle = Bundle(path: path),
          let executableName = appBundle.executableURL?.lastPathComponent else {
        return bundleID
    }
    return executableName
}

extension String {
  /// This converts string to UInt as a fourCharCode
  public var fourCharCodeValue: Int {
    var result: Int = 0
    if let data = self.data(using: String.Encoding.macOSRoman) {
      data.withUnsafeBytes({ (rawBytes) in
        let bytes = rawBytes.bindMemory(to: UInt8.self)
        for i in 0 ..< data.count {
          result = result << 8 + Int(bytes[i])
        }
      })
    }
    return result
  }
}

class HotkeyListener {
  static
  func getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = cocoaFlags.rawValue
    var newFlags: Int = 0

    if ((flags & NSEvent.ModifierFlags.control.rawValue) > 0) {
      newFlags |= controlKey
    }

    if ((flags & NSEvent.ModifierFlags.command.rawValue) > 0) {
      newFlags |= cmdKey
    }

    if ((flags & NSEvent.ModifierFlags.shift.rawValue) > 0) {
      newFlags |= shiftKey;
    }

    if ((flags & NSEvent.ModifierFlags.option.rawValue) > 0) {
      newFlags |= optionKey
    }

    if ((flags & NSEvent.ModifierFlags.capsLock.rawValue) > 0) {
      newFlags |= alphaLock
    }

    return UInt32(newFlags);
  }

  static func register() {
    var hotKeyRef: EventHotKeyRef?
    let modifierFlags: UInt32 =
      getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags.command)

    let keyCode = kVK_ANSI_Period
    var gMyHotKeyID = EventHotKeyID()

    gMyHotKeyID.id = UInt32(keyCode)

    // Not sure what "swat" vs "htk1" do.
    gMyHotKeyID.signature = OSType("swat".fourCharCodeValue)
    // gMyHotKeyID.signature = OSType("htk1".fourCharCodeValue)

    var eventType = EventTypeSpec()
    eventType.eventClass = OSType(kEventClassKeyboard)
    eventType.eventKind = OSType(kEventHotKeyPressed)

    // Install handler.
    InstallEventHandler(GetApplicationEventTarget(), {
      (nextHanlder, theEvent, userData) -> OSStatus in
      // var hkCom = EventHotKeyID()

      // GetEventParameter(theEvent,
      //                   EventParamName(kEventParamDirectObject),
      //                   EventParamType(typeEventHotKeyID),
      //                   nil,
      //                   MemoryLayout<EventHotKeyID>.size,
      //                   nil,
      //                   &hkCom)

      NSLog("Command + . Pressed!")
//        NSWorkspace.shared.hideOtherApplications()
        NSApplication.shared.activate(ignoringOtherApps: true)

      return noErr
      /// Check that hkCom in indeed your hotkey ID and handle it.
    }, 1, &eventType, nil, nil)

    // Register hotkey.
    let status = RegisterEventHotKey(UInt32(keyCode),
                                     modifierFlags,
                                     gMyHotKeyID,
                                     GetApplicationEventTarget(),
                                     0,
                                     &hotKeyRef)
    assert(status == noErr)    
  }
}
