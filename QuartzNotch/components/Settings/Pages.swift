
import Defaults
import SwiftUI

struct Pages: View {
    private enum BackgroundStyle: String, CaseIterable, Identifiable {
        case classic = "Classic"
        case semiLiquidGlass = "Semi liquid glass"

        var id: String { rawValue }
    }

    @ObservedObject private var coordinator = QuartzViewCoordinator.shared
    @Default(.pageHomeEnabled) private var pageHomeEnabled
    @Default(.pageShelfEnabled) private var pageShelfEnabled

    @Default(.pageThirdEnabled) private var pageThirdEnabled
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground

    private var backgroundStyleBinding: Binding<BackgroundStyle> {
        Binding(
            get: {
                pageUseLiquidGlassBackground ? .semiLiquidGlass : .classic
            },
            set: { newValue in
                pageUseLiquidGlassBackground = (newValue == .semiLiquidGlass)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { pageHomeEnabled },
                    set: { newValue in
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
                        if !newValue && !pageHomeEnabled && !pageShelfEnabled {
                            pageHomeEnabled = true
                        }
                        pageThirdEnabled = newValue
                    }
                )) {
                    Text("Page 3 (Custom)")
                }

                Toggle("Show page dots", isOn: $coordinator.alwaysShowTabs)
                LabeledContent("Background style") {
                    AccentMenuPicker(
                        selection: backgroundStyleBinding,
                        options: BackgroundStyle.allCases,
                        title: { $0.rawValue }
                    )
                }
            } header: {
                Text("Pages")
            } footer: {
                if pageUseLiquidGlassBackground {
                    Text("⚠ Semi liquid glass mode is still experimental and may occasionally present visual bugs or slight stutters. On systems without native liquid glass, QuartzNotch now uses a compatibility fallback automatically.")
                }
            }
        }
        .navigationTitle("Pages")
    }
}
