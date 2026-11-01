import SwiftUI

public enum MacProTheme {
    // Fondo Cósmico (Dualidad Azul Neón & Rojo Neón Switch)
    public static let bgDeepMidnight = Color(red: 0.04, green: 0.05, blue: 0.11) // #0A0D1C
    public static let bgRoyalIndigo  = Color(red: 0.08, green: 0.06, blue: 0.20) // #141033
    public static let bgCosmicPlum   = Color(red: 0.18, green: 0.04, blue: 0.16) // #2E0A29

    // Acentos Neón Switch: Azul Eléctrico y Rojo Neón
    public static let neonBlue       = Color(red: 0.00, green: 0.65, blue: 1.00) // #00A6FF (Joy-Con Azul)
    public static let neonCyan       = Color(red: 0.00, green: 0.84, blue: 1.00) // #00D6FF
    public static let neonRed        = Color(red: 1.00, green: 0.22, blue: 0.36) // #FF385C (Joy-Con Rojo)
    public static let vibrantCrimson = Color(red: 0.95, green: 0.10, blue: 0.25) // #F21A40
    
    // Acentos Auxiliares
    public static let emeraldGreen   = Color(red: 0.12, green: 0.88, blue: 0.55) // #1FE08C
    public static let solarAmber     = Color(red: 1.00, green: 0.72, blue: 0.18) // #FFB82E

    // Superficies de Cristal (Glassmorphic)
    public static let glassFill            = Color.white.opacity(0.07)
    public static let glassFillSubtle      = Color.white.opacity(0.04)
    public static let glassSelected        = Color.white.opacity(0.16)
    public static let glassBorder          = Color.white.opacity(0.13)
    public static let glassBorderSelected  = Color.white.opacity(0.30)
    public static let glassTextMuted       = Color.white.opacity(0.65)

    // Gradientes Duales Azul & Rojo
    public static let switchDualGradient = LinearGradient(
        colors: [neonBlue, neonRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let blueGradient = LinearGradient(
        colors: [neonCyan, neonBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let redGradient = LinearGradient(
        colors: [neonRed, vibrantCrimson],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public struct CosmicCanvasBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            // Fondo base oscuro profundo
            LinearGradient(
                colors: [MacProTheme.bgDeepMidnight, MacProTheme.bgRoyalIndigo, MacProTheme.bgCosmicPlum],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Resplandor Azul Neón a la izquierda
            RadialGradient(
                colors: [MacProTheme.neonBlue.opacity(0.28), Color.clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 700
            )
            // Resplandor Rojo Neón a la derecha
            RadialGradient(
                colors: [MacProTheme.neonRed.opacity(0.26), Color.clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 750
            )
            // Glow central sutil
            RadialGradient(
                colors: [MacProTheme.neonCyan.opacity(0.10), Color.clear],
                center: .center,
                startRadius: 60,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}

public struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? MacProTheme.glassSelected : MacProTheme.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? MacProTheme.glassBorderSelected : MacProTheme.glassBorder, lineWidth: 0.5)
            )
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 14, isSelected: Bool = false) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}
