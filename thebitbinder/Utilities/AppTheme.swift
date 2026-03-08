//
//  AppTheme.swift
//  thebitbinder
//
//  Created on 2/18/26.
//

import SwiftUI

// MARK: - App Theme
/// Centralized design system — looks & feels like a comedian's actual notebook
/// Yellowed paper, blue ballpoint ink, red margin lines, coffee-stained edges
struct AppTheme {

    // MARK: - Colors
    struct Colors {
        // ── Core brand ───────────────────────────────────────
        static let brand      = Color(red: 0.18, green: 0.32, blue: 0.62)
        static let brandDeep  = Color(red: 0.12, green: 0.22, blue: 0.48)
        static let brandLight = Color(red: 0.55, green: 0.68, blue: 0.88)

        // ── Ink ──────────────────────────────────────────────
        static let inkBlack = Color(red: 0.11, green: 0.09, blue: 0.09)
        static let inkBlue  = Color(red: 0.18, green: 0.32, blue: 0.62)
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

        // ── Semantic ─────────────────────────────────────────
        static let success = Color(red: 0.22, green: 0.58, blue: 0.35)      // Green ink
        static let warning = Color(red: 0.82, green: 0.58, blue: 0.12)      // Orange highlighter
        static let error   = inkRed                                          // Red pen
        static let info    = inkBlue                                         // Blue pen

        // ── Section accents ──────────────────────────────────
        static let notepadAccent   = inkBlue
        static let brainstormAccent = Color(red: 0.95, green: 0.70, blue: 0.15)  // Warm yellow/gold for ideas
        static let jokesAccent     = Color(red: 0.84, green: 0.50, blue: 0.12)
        static let setsAccent      = Color(red: 0.48, green: 0.36, blue: 0.68)
        static let recordingsAccent = inkRed
        static let notebookAccent  = Color(red: 0.52, green: 0.38, blue: 0.24)
        static let settingsAccent  = Color(red: 0.42, green: 0.42, blue: 0.45)
        static let aiAccent        = Color(red: 0.40, green: 0.33, blue: 0.72)
        static let roastAccent     = Color(red: 0.92, green: 0.28, blue: 0.12)

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
        static let aiGradient      = LinearGradient(colors: [aiAccent, Color(red: 0.32, green: 0.22, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
    /// Add a bottom border line to a view
    func borderBottom(color: Color = Color(.systemGray3), width: CGFloat = 1) -> some View {
        VStack(spacing: 0) {
            self
            Divider()
                .background(color)
                .frame(height: width)
        }
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
