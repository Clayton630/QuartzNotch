//
// AppIcons.swift
// boringNotch
//
// Created by Harsh Vardhan Goswami on 16/08/24.
//

import SwiftUI
import AppKit

struct AppIcons {
    
    func getIcon(file path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path)
        else { return nil }
        
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    func getIcon(bundleID: String) -> NSImage? {
        guard let path = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        )?.absoluteString
        else { return nil }
        
        return getIcon(file: path)
    }
    
  /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }
        
        return Bundle(url: url)
    }
    
}

func AppIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }
    
    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

enum ProviderAppIconResolver {
    static func icon(forProviderName providerName: String) -> NSImage? {
        let trimmed = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let workspace = NSWorkspace.shared
        let normalized = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalized.contains("raccourci") || normalized.contains("shortcut") {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                return workspace.icon(forFile: appURL.path)
            }
        }

        if let appPath = workspace.fullPath(forApplication: trimmed) {
            return workspace.icon(forFile: appPath)
        }

        if let appPath = workspace.fullPath(forApplication: "\(trimmed).app") {
            return workspace.icon(forFile: appPath)
        }

        return nil
    }
}
