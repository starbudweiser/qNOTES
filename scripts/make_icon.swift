// Dessine l'icône de qNOTES : une page de notes (titre, puces, tâche cochée) sur fond sombre, à plat (Socle).
// Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let accent = NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
let background = NSColor(white: 0.118, alpha: 1)
let paper = NSColor(white: 0.17, alpha: 1)
let ink = NSColor(white: 0.86, alpha: 1)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

func round(_ r: CGRect, _ radius: CGFloat, _ color: NSColor) {
    cg.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.setFillColor(color.cgColor)
    cg.fillPath()
}

// Gabarit macOS : carré arrondi de 824 px centré.
round(CGRect(x: 100, y: 100, width: 824, height: 824), 185, background)
// Page
round(CGRect(x: 262, y: 200, width: 500, height: 624), 54, paper)
// Titre
round(CGRect(x: 332, y: 690, width: 300, height: 46), 23, accent)
// Lignes : puce + texte
let rows: [(CGFloat, CGFloat)] = [(590, 330), (500, 260), (410, 300)]
for (y, w) in rows {
    cg.setFillColor(accent.cgColor)
    cg.fillEllipse(in: CGRect(x: 332, y: y + 6, width: 30, height: 30))
    round(CGRect(x: 392, y: y + 8, width: w, height: 26), 13, ink)
}
// Tâche cochée
round(CGRect(x: 328, y: 316, width: 40, height: 40), 10, accent)
cg.setStrokeColor(background.cgColor)
cg.setLineWidth(9)
cg.setLineCap(.round); cg.setLineJoin(.round)
cg.move(to: CGPoint(x: 337, y: 337)); cg.addLine(to: CGPoint(x: 346, y: 327)); cg.addLine(to: CGPoint(x: 361, y: 346))
cg.strokePath()
round(CGRect(x: 392, y: 318, width: 230, height: 26), 13, NSColor(white: 0.45, alpha: 1))

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
