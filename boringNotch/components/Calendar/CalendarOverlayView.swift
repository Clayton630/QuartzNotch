import SwiftUI
import Defaults

struct CalendarOverlayView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    @State private var selectedDate = Date()

    private let leadingGutterWidth: CGFloat = 6

    private var selectedMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: selectedDate)
        return month.prefix(1).uppercased() + month.dropFirst()
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Color.clear

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1)
                    .padding(.leading, 0)
                    .padding(.vertical, 12)
            }
            .frame(width: leadingGutterWidth)

            CalendarView(selectedDate: $selectedDate)
                .padding(.trailing, 8)
        }
        .background(pageUseLiquidGlassBackground ? Color.clear : Color.black)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: cornerRadiusInsets.opened.bottom,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
        .contentShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: cornerRadiusInsets.opened.bottom,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
        .clipped()
        .overlay(alignment: .topLeading) {
            Text(selectedMonthTitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.red)
                .padding(.top, -31)
                .padding(.leading, CGFloat(leadingGutterWidth) + 4)
                .allowsHitTesting(false)
        }
        .onHover { isHovering in
            vm.isHoveringCalendar = isHovering
        }
    }
}
