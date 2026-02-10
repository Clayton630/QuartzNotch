//
// Pages.swift
// boringNotch
//
// Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct Pages: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.pageHomeEnabled) private var pageHomeEnabled
    @Default(.pageShelfEnabled) private var pageShelfEnabled

@Default(.pageThirdEnabled) private var pageThirdEnabled
    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { pageHomeEnabled },
                    set: { newValue in
            // Never allow both pages to be disabled.
                        if !newValue && !pageShelfEnabled {
                            pageShelfEnabled = true
                        }
                        pageHomeEnabled = newValue
                    }
                )) {
                    Text("Page 1 (Media controls)")
                }

                Toggle(isOn: Binding(
                    get: { pageShelfEnabled },
                    set: { newValue in
            // Never allow both pages to be disabled.
                        if !newValue && !pageHomeEnabled {
                            pageHomeEnabled = true
                        }
                        pageShelfEnabled = newValue
                    }
                )) {
                    Text("Page 2 (Shelf + Share)")
                }


Toggle(isOn: Binding(
    get: { pageThirdEnabled },
    set: { newValue in
    // Never allow 0 active pages.
        if !newValue && !pageHomeEnabled && !pageShelfEnabled {
            pageHomeEnabled = true
        }
        pageThirdEnabled = newValue
    }
)) {
    Text("Page 3 (Custom)")
}

                Toggle("Show page dots", isOn: $coordinator.alwaysShowTabs)
            } header: {
                Text("Pages")
            } footer: {
                Text("These toggles control which pages are available when the notch is open. At least one page must remain enabled.")
            }
        }
        .navigationTitle("Pages")
    }
}
