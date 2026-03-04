//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import SwiftUI

struct NotchShape: InsettableShape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    private var useExactBounds: Bool
    private var insetAmount: CGFloat = 0

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil,
        useExactBounds: Bool = false
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
        self.useExactBounds = useExactBounds
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            // In exact-bounds mode (used by the deployed notch), keep top corners
            // non-animated to avoid the transient inward rounding at open start.
            if !useExactBounds {
                topCornerRadius = newValue.first
            }
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        if useExactBounds {
            return exactBoundsPath(in: insetRect)
        }
        return legacyPath(in: insetRect)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func legacyPath(in rect: CGRect) -> Path {
        var path = Path()
        let topRadius = max(0, topCornerRadius - insetAmount)
        let bottomRadius = max(0, bottomCornerRadius - insetAmount)

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.minY + topRadius
            ),
            control: CGPoint(
                x: rect.minX + topRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.maxY - bottomRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topRadius + bottomRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius - bottomRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.maxY - bottomRadius
            ),
            control: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.minY + topRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }

    private func exactBoundsPath(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let top = min(max(0, topCornerRadius - insetAmount), min((maxX - minX) / 2, (maxY - minY) / 2))
        let bottom = min(max(0, bottomCornerRadius - insetAmount), min((maxX - minX) / 2, (maxY - minY) / 2))
        path.move(to: CGPoint(x: minX + top, y: minY))
        path.addLine(to: CGPoint(x: maxX - top, y: minY))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY + top),
            control: CGPoint(x: maxX, y: minY)
        )

        path.addLine(to: CGPoint(x: maxX, y: maxY - bottom))

        path.addQuadCurve(
            to: CGPoint(x: maxX - bottom, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + bottom, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - bottom),
            control: CGPoint(x: minX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX, y: minY + top))
        path.addQuadCurve(
            to: CGPoint(x: minX + top, y: minY),
            control: CGPoint(x: minX, y: minY)
        )

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
