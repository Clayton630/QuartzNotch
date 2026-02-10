import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A DropDelegate implementation used by ContentView to handle general drop operations.
/// It tracks whether the drop target is currently active and forwards dropped items to ShelfStateViewModel.
struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    
    private let supportedTypes: [UTType] = [
        .fileURL,
        .url,
        .utf8PlainText,
        .plainText,
        .data
    ]
    
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: supportedTypes)
    }
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        
        let providers = info.itemProviders(for: supportedTypes)
        if !providers.isEmpty {
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        return false
    }
}
