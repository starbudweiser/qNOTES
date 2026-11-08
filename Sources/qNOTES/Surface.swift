import SwiftUI

/// Fond d'une zone : couleur du thème, ou — avec « Fond translucide » — matière floue pour le fond général et couleur
/// légère pour les zones posées dessus.
struct SurfaceBackground: ViewModifier {
    let color: Color
    let base: Bool
    @AppStorage(Prefs.translucent) private var translucent = false

    func body(content: Content) -> some View {
        content.background(translucent ? (base ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(color.opacity(0.35))) : AnyShapeStyle(color))
    }
}

extension View {
    func surfaceBackground(_ color: Color, base: Bool = false) -> some View { modifier(SurfaceBackground(color: color, base: base)) }
}
