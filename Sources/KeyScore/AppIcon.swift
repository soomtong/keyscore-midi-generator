import AppKit

/// 앱 아이콘 아트워크. 런타임 Dock 아이콘과 .icns 생성에 같은 코드를 쓴다.
enum AppIcon {
    // (column, row, length) — 피아노 롤 위로 올라가는 멜로디
    private static let notes: [(Double, Double, Double)] = [
        (0.0, 0, 2), (2.5, 1, 1.5), (1.0, 2, 1), (4.0, 2, 2), (2.0, 3, 2),
        (5.0, 3.5 + 0, 1.5), (3.5, 4, 1), (5.8, 4.5, 1.3), (0.5, 5, 1.5), (4.5, 5.5, 1),
    ]

    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    static func draw(in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = rect.width / 1024
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)

        // macOS 아이콘 본체: 1024 캔버스 안의 824 라운드 사각형
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(red: 0.10, green: 0.07, blue: 0.25, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let bg = CGGradient(colorsSpace: space, colors: [
            NSColor(red: 0.43, green: 0.24, blue: 0.93, alpha: 1).cgColor,
            NSColor(red: 0.12, green: 0.08, blue: 0.33, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 820, y: 100), options: [])

        // 피아노 롤 그리드
        let grid = CGRect(x: 170, y: 190, width: 684, height: 644)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(3)
        for i in 0...7 {
            let x = grid.minX + grid.width * Double(i) / 7
            ctx.move(to: CGPoint(x: x, y: grid.minY)); ctx.addLine(to: CGPoint(x: x, y: grid.maxY))
        }
        for j in 0...6 {
            let y = grid.minY + grid.height * Double(j) / 6
            ctx.move(to: CGPoint(x: grid.minX, y: y)); ctx.addLine(to: CGPoint(x: grid.maxX, y: y))
        }
        ctx.strokePath()

        // 노트 막대
        let colW = grid.width / 7.5
        let rowH = grid.height / 6.5
        let barH = rowH * 0.62
        var bars = notes.map { col, row, len in
            (rect: CGRect(x: grid.minX + col * colW, y: grid.minY + row * rowH + (rowH - barH) / 2,
                          width: len * colW - 10, height: barH),
             t: row / 6)
        }
        // 노트 묶음의 경계 상자를 그리드 중심에 맞춘다
        let bounds = bars.dropFirst().reduce(bars[0].rect) { $0.union($1.rect) }
        let dx = grid.midX - bounds.midX
        let dy = grid.midY - bounds.midY
        bars = bars.map { (rect: $0.rect.offsetBy(dx: dx, dy: dy), t: $0.t) }

        for (r, t) in bars {
            let color = NSColor(hue: 0.50 + 0.42 * t, saturation: 0.70, brightness: 1, alpha: 1)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 22, color: color.withAlphaComponent(0.65).cgColor)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 상단 하이라이트
        let hl = CGGradient(colorsSpace: space, colors: [
            NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(hl, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
        ctx.restoreGState()

        ctx.restoreGState()
    }

    /// 정확히 pixels x pixels 크기의 PNG 데이터.
    static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// `KeyScore --export-iconset <dir>`: iconutil 용 iconset 을 쓴다.
    static func exportIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png(pixels: base * scale)?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
    }
}
