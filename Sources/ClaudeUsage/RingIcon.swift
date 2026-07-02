import AppKit

enum RingIcon {

    static func make(fiveHourPercent: Double?, weeklyPercent: Double?, isStale: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)

            drawTrack(center: center, radius: 7.5, lineWidth: 2.5)
            drawTrack(center: center, radius: 4.0, lineWidth: 2.5)

            if let fiveHourPercent {
                drawArc(center: center, radius: 7.5, lineWidth: 2.5,
                        percent: fiveHourPercent, color: color(for: fiveHourPercent, base: .systemBlue, isStale: isStale))
            }
            if let weeklyPercent {
                drawArc(center: center, radius: 4.0, lineWidth: 2.5,
                        percent: weeklyPercent, color: color(for: weeklyPercent, base: .systemPurple, isStale: isStale))
            }

            if isStale {
                drawErrorBadge(in: rect)
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawTrack(center: NSPoint, radius: CGFloat, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        path.lineWidth = lineWidth
        NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setStroke()
        path.stroke()
    }

    private static func drawArc(center: NSPoint, radius: CGFloat, lineWidth: CGFloat, percent: Double, color: NSColor) {
        let clamped = max(0, min(100, percent))
        guard clamped > 0 else { return }

        // Start at 12 o'clock (90deg in AppKit's coordinate system) and sweep clockwise.
        let startAngle: CGFloat = 90
        let sweep = CGFloat(clamped / 100.0) * 360.0
        let endAngle = startAngle - sweep

        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func drawErrorBadge(in rect: NSRect) {
        let badgeSize: CGFloat = 6
        let badgeRect = NSRect(x: rect.maxX - badgeSize, y: rect.maxY - badgeSize, width: badgeSize, height: badgeSize)
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.systemRed.setFill()
        badgePath.fill()
    }

    /// Each ring keeps a distinct base color while healthy so the two rings read as
    /// separate signals at a glance; both converge to orange/red once usage gets risky.
    private static func color(for percent: Double, base: NSColor, isStale: Bool) -> NSColor {
        if isStale {
            return NSColor.tertiaryLabelColor
        }
        switch percent {
        case ..<70:
            return base
        case 70..<90:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}
