//
// CalendarOverlayView.swift
// boringNotch
//
// Created by Clayton on 20/01/2026.
//
import SwiftUI

struct CalendarOverlayView: View {
    @EnvironmentObject var vm: BoringViewModel

  // Left gutter that visually belongs to the calendar panel.
  // It hosts the separator and adds breathing room from the pager.
  // Keep it small, but place the separator further away from the calendar content.
    private let leadingGutterWidth: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
      // Gutter + separator
            ZStack(alignment: .leading) {
                Color.clear

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1)
          // Put the line closer to the pager side (left), so it's not hugging the calendar.
                    .padding(.leading, 0)
                    .padding(.vertical, 12)
            }
            .frame(width: leadingGutterWidth)

      // Calendar content
            CalendarView()
                .padding(8)
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipped()
        .onHover { isHovering in
            vm.isHoveringCalendar = isHovering
        }
    }
}
