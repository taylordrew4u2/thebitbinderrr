//
//  AppTheme.swift
//  thebitbinder
//
//  Centralized design system for BitBinder
//  Evidence-based visual design following research principles:
//  - Blue for primary actions (trust, calm confidence)
//  - Green for success/completion/synced states
//  - Red reserved for destructive/error/urgent only
//  - Strong contrast, rounded geometry, restrained palette
//

import SwiftUI

// MARK: - App Theme
/// Centralized design system — looks & feels like a comedian's actual notebook
/// Yellowed paper, blue ballpoint ink, red margin lines, coffee-stained edges
struct AppTheme {

    // MARK: - Colors
    struct Colors {
        // ── Primary Action (Blue - trust, confidence, primary interactions) ──
        static let primaryAction     = Color(red: 0.20, green: 0.40, blue: 0.70)  // Trustworthy blue
        static let primaryActionDeep = Color(red: 0.14, green: 0.30, blue: 0.55)
        static let primaryActionLight = Color(red: 0.45, green: 0.62, blue: 0.85)
        
        // ── Core brand (legacy compatibility) ───────────────────────────────
        static let brand      = primaryAction
        static let brandDeep  = primaryActionDeep
        static let brandLight = primaryActionLight

        // ── Ink ──────────────────────────────────────────────
        static let inkBlack = Color(red: 0.11, green: 0.09, blue: 0.09)
        static let inkBlue  = primaryAction
        static let inkRed   = Color(red: 0.72, green: 0.20, blue: 0.16)

        // ── Paper ────────────────────────────────────────────
        static let paperCream    = Color(red: 0.975, green: 0.960, blue: 0.920)
        static let paperAged     = Color(red: 0.950, green: 0.930, blue: 0.885)
        static let paperDeep     = Color(red: 0.920, green: 0.900, blue: 0.855)
        static let paperLine     = Color(red: 0.62, green: 0.72, blue: 0.86).opacity(0.38)
        static let marginRed     = Color(red: 0.80, green: 0.28, blue: 0.24).opacity(0.32)
        static let coffeeStain   = Color(red: 0.68, green: 0.54, blue: 0.34).opacity(0.07)

        // ── Surfaces ─────────────────────────────────────────
        static let surface         = paperCream
        static let surfaceElevated = Color(red: 0.99, green: 0.975, blue: 0.940)
        static let surfaceTertiary = Color(red: 0.75, green: 0.71, blue: 0.64)
        static let divider         = Color(red: 0.82, green: 0.78, blue: 0.70).opacity(0.50)

        // ── Text ─────────────────────────────────────────────
        static let textPrimary   = inkBlack
        static let textSecondary = Color(red: 0.36, green: 0.33, blue: 0.30)
        static let textTertiary  = Color(red: 0.55, green: 0.52, blue: 0.47)

        // ── Semantic (evidence-based color roles) ────────────
        static let success = Color(red: 0.18, green: 0.55, blue: 0.34)      // Green - completion, synced, ready
        static let warning = Color(red: 0.82, green: 0.58, blue: 0.12)      // Amber - attention needed
        static let error   = inkRed                                          // Red - destructive, errors only
        static let info    = primaryAction                                   // Blue - informational
        
        // ── The Hits (gold/star - perfected jokes) ───────────
        static let hitsGold      = Color(red: 0.90, green: 0.72, blue: 0.20)
        static let hitsGoldLight = Color(red: 0.95, green: 0.85, blue: 0.50)

        // ── Unified Section Accent (use primary blue consistently) ──
        // All sections now use primaryAction for consistency
        // Legacy names maintained for compatibility but map to unified colors
        static let notepadAccent    = primaryAction
        static let brainstormAccent = Color(red: 0.85, green: 0.65, blue: 0.18)  // Warm gold for ideas
        static let jokesAccent      = primaryAction  // Changed from orange to blue
        static let setsAccent       = primaryAction  // Unified
        static let recordingsAccent = Color(red: 0.65, green: 0.25, blue: 0.20)  // Subtle red for recordings
        static let notebookAccent   = Color(red: 0.52, green: 0.38, blue: 0.24)  // Leather brown
        static let settingsAccent   = Color(red: 0.42, green: 0.42, blue: 0.45)
        static let aiAccent         = primaryAction
        static let roastAccent      = Color(red: 0.92, green: 0.28, blue: 0.12)

        // ── Roast mode surfaces ──────────────────────────────
        static let roastBackground = Color(red: 0.09, green: 0.07, blue: 0.07)
        static let roastSurface    = Color(red: 0.13, green: 0.10, blue: 0.09)
        static let roastCard       = Color(red: 0.17, green: 0.13, blue: 0.11)
        static let roastLine       = roastAccent.opacity(0.18)

        static let roastHeaderGradient = LinearGradient(
            colors: [Color(red: 0.17, green: 0.07, blue: 0.04), Color(red: 0.09, green: 0.05, blue: 0.03)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let roastEmberGradient = LinearGradient(
            colors: [Color(red: 1.0, green: 0.70, blue: 0.08), roastAccent, Color(red: 0.65, green: 0.10, blue: 0.03)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        // ── Gradients ────────────────────────────────────────
        static let brandGradient = LinearGradient(colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let surfaceGradient = LinearGradient(colors: [paperCream, paperAged], startPoint: .top, endPoint: .bottom)
        static let heroGradient    = LinearGradient(colors: [paperCream, surface], startPoint: .top, endPoint: .bottom)
        static let leatherGradient = LinearGradient(
            colors: [Color(red: 0.38, green: 0.26, blue: 0.16), Color(red: 0.28, green: 0.18, blue: 0.10)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Typography
    struct Typography {
        static let display   = Font.system(size: 34, weight: .bold,     design: .serif)
        static let largeTitle = Font.system(size: 28, weight: .bold,    design: .serif)
        static let title     = Font.system(size: 22, weight: .semibold, design: .serif)
        static let title3    = Font.system(size: 20, weight: .semibold, design: .serif)
        static let headline  = Font.system(size: 17, weight: .semibold, design: .serif)
        static let body      = Font.system(size: 16, weight: .regular,  design: .default)
        static let callout   = Font.system(size: 15, weight: .medium,   design: .default)
        static let subheadline = Font.system(size: 14, weight: .regular, design: .default)
        static let caption   = Font.system(size: 12, weight: .medium,   design: .default)
        static let caption2  = Font.system(size: 11, weight: .regular,  design: .default)
        static let scrawl    = Font.system(size: 20, weight: .heavy,    design: .serif)
    }

    // MARK: - Spacing (8-pt grid)
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radius
    struct Radius {
        static let xs:     CGFloat = 4
        static let small:  CGFloat = 6
        static let medium: CGFloat = 10
        static let large:  CGFloat = 14
        static let xl:     CGFloat = 20
        static let pill:   CGFloat = 999
    }

    // MARK: - Shadows
    struct Shadows {
        /// Subtle lift — use on list rows
        static let sm  = (color: Color.black.opacity(0.06), radius: CGFloat(4),  x: CGFloat(0), y: CGFloat(2))
        /// Card elevation — use on cards / panels
        static let md  = (color: Color.black.opacity(0.10), radius: CGFloat(8),  x: CGFloat(0), y: CGFloat(3))
        /// Floating elements — FABs, menus
        static let lg  = (color: Color.black.opacity(0.16), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(6))
        /// Inner page shadow
        static let inner = (color: Color.black.opacity(0.08), radius: CGFloat(6), x: CGFloat(2), y: CGFloat(0))
    }
}

// MARK: - Extensions

extension Color {
    /// Create a color from a hex string (e.g., "FFF9C4")
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        
        guard scanner.scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    /// Make any view feel alive on press — scale down + haptic
    func touchReactive(scale: CGFloat = 0.92, haptic: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.buttonStyle(TouchReactiveStyle(pressedScale: scale, hapticStyle: haptic))
    }

    /// Subtle press effect for cards/rows — lighter scale + no haptic
    func cardPress() -> some View {
        self.buttonStyle(TouchReactiveStyle(pressedScale: 0.97, hapticStyle: nil))
    }

    /// Heavy press for primary actions — deeper scale + medium haptic
    func heavyPress() -> some View {
        self.buttonStyle(TouchReactiveStyle(pressedScale: 0.88, hapticStyle: .medium))
    }
}

// MARK: - Touch Reactive Button Style

/// Reusable button style: scale animation + optional haptic on press
struct TouchReactiveStyle: ButtonStyle {
    let pressedScale: CGFloat
    let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            // Performance: Use faster, simpler animation
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// FAB-specific style: bouncy scale + glow pulse on press
struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .brightness(configuration.isPressed ? 0.08 : 0)
            // Performance: Use faster animation for immediate feedback
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Menu row style: slide right + highlight on press
struct MenuItemStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0, anchor: .leading)
            .offset(x: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            // Performance: Use faster animation
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Chip/tag press style: pop scale
struct ChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            // Performance: Use faster animation
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Cross-platform helpers

/// Dismiss the keyboard on iOS; no-op on macOS Catalyst
func dismissKeyboard() {
#if !targetEnvironment(macCatalyst)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}

/// Open a URL — UIApplication on iOS and Mac Catalyst
func openURL(_ url: URL) {
    UIApplication.shared.open(url)
}
