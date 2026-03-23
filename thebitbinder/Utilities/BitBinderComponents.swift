//
//  BitBinderComponents.swift
//  thebitbinder
//
//  Shared design components for consistent UI across the app
//  Evidence-based design: rounded corners, clear hierarchy, strong contrast
//

import SwiftUI

// MARK: - Empty State Component

/// Unified empty state for all sections - deliberate, designed, helpful
struct BitBinderEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var roastMode: Bool = false
    var iconGradient: LinearGradient? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon with glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.15),
                                (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.03)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 110, height: 110)
                
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        iconGradient ?? LinearGradient(
                            colors: [
                                roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction,
                                (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Text
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 32)
            
            // Action button (if provided)
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                        )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.95, hapticStyle: .light))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Chip Component

/// Unified chip for tags, folders, filters
struct BitBinderChip: View {
    let text: String
    var icon: String? = nil
    var isSelected: Bool = false
    var style: ChipVariant = .filter
    var roastMode: Bool = false
    var action: (() -> Void)? = nil
    
    enum ChipVariant {
        case filter     // Folder/category filter chips
        case tag        // Tag chips on cards
        case status     // Status badges
    }
    
    private var backgroundColor: Color {
        switch style {
        case .filter:
            if isSelected {
                return roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction
            }
            return roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.paperAged
        case .tag:
            return (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.12)
        case .status:
            return AppTheme.Colors.success.opacity(0.15)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filter:
            if isSelected {
                return .white
            }
            return roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary
        case .tag:
            return roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction
        case .status:
            return AppTheme.Colors.success
        }
    }
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    chipContent
                }
                .buttonStyle(ChipStyle())
            } else {
                chipContent
            }
        }
    }
    
    private var chipContent: some View {
        HStack(spacing: 4) {
            if let icon = icon, isSelected || style != .filter {
                Image(systemName: icon)
                    .font(.system(size: style == .tag ? 9 : 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: style == .tag ? 11 : 13, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, style == .tag ? 8 : 14)
        .padding(.vertical, style == .tag ? 4 : 7)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .foregroundColor(foregroundColor)
    }
}

// MARK: - Badge Component

/// Small badges for status, confidence, counts
struct BitBinderBadge: View {
    let text: String
    var icon: String? = nil
    var variant: BadgeVariant = .neutral
    var size: BadgeSize = .small
    var roastMode: Bool = false
    
    enum BadgeVariant {
        case neutral
        case success    // Green - synced, approved, hit
        case warning    // Amber - needs attention
        case error      // Red - failed, conflict
        case gold       // Gold - The Hits
        case info       // Blue - informational
    }
    
    enum BadgeSize {
        case small
        case medium
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .neutral: return roastMode ? .white.opacity(0.1) : AppTheme.Colors.paperDeep
        case .success: return AppTheme.Colors.success.opacity(0.15)
        case .warning: return AppTheme.Colors.warning.opacity(0.15)
        case .error: return AppTheme.Colors.error.opacity(0.15)
        case .gold: return AppTheme.Colors.hitsGold.opacity(0.2)
        case .info: return AppTheme.Colors.primaryAction.opacity(0.12)
        }
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .neutral: return roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary
        case .success: return AppTheme.Colors.success
        case .warning: return AppTheme.Colors.warning
        case .error: return AppTheme.Colors.error
        case .gold: return AppTheme.Colors.hitsGold
        case .info: return AppTheme.Colors.primaryAction
        }
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return 12
        }
    }
    
    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: fontSize - 1, weight: .semibold))
            }
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
        }
        .padding(.horizontal, size == .small ? 6 : 8)
        .padding(.vertical, size == .small ? 3 : 4)
        .background(
            Capsule().fill(backgroundColor)
        )
        .foregroundColor(foregroundColor)
    }
}

// MARK: - Card Container

/// Unified card wrapper with consistent styling
struct BitBinderCard<Content: View>: View {
    var roastMode: Bool = false
    var elevation: CardElevation = .medium
    @ViewBuilder let content: Content
    
    enum CardElevation {
        case flat
        case low
        case medium
        case high
    }
    
    private var shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        switch elevation {
        case .flat: return (Color.clear, 0, 0, 0)
        case .low: return AppTheme.Shadows.sm
        case .medium: return AppTheme.Shadows.md
        case .high: return AppTheme.Shadows.lg
        }
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            )
    }
}

// MARK: - Section Header

/// Consistent section header styling
struct BitBinderSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    var roastMode: Bool = false
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            if let trailing = trailing {
                trailing
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Hit Star Badge

/// Gold star indicator for "The Hits" (perfected jokes)
struct HitStarBadge: View {
    var size: CGFloat = 20
    var showBackground: Bool = true
    var roastMode: Bool = false
    
    var body: some View {
        ZStack {
            if showBackground {
                Circle()
                    .fill(AppTheme.Colors.hitsGold.opacity(0.2))
                    .frame(width: size + 8, height: size + 8)
            }
            
            Image(systemName: roastMode ? "flame.fill" : "star.fill")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: roastMode 
                            ? [AppTheme.Colors.roastAccent, .orange]
                            : [AppTheme.Colors.hitsGold, AppTheme.Colors.hitsGoldLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

// MARK: - Confidence Badge

/// Import confidence indicator
struct ConfidenceBadge: View {
    let level: ConfidenceLevel
    var roastMode: Bool = false
    
    enum ConfidenceLevel: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case review = "Review"
    }
    
    private var variant: BitBinderBadge.BadgeVariant {
        switch level {
        case .high: return .success
        case .medium: return .info
        case .low: return .warning
        case .review: return .neutral
        }
    }
    
    private var icon: String {
        switch level {
        case .high: return "checkmark.circle.fill"
        case .medium: return "circle.fill"
        case .low: return "exclamationmark.circle.fill"
        case .review: return "eye.fill"
        }
    }
    
    var body: some View {
        BitBinderBadge(
            text: level.rawValue,
            icon: icon,
            variant: variant,
            size: .small,
            roastMode: roastMode
        )
    }
}

// MARK: - Toolbar Background Modifier

/// Consistent toolbar styling
struct BitBinderToolbar: ViewModifier {
    var roastMode: Bool = false
    
    func body(content: Content) -> some View {
        content
            .toolbarBackground(
                roastMode ? AnyShapeStyle(AppTheme.Colors.roastSurface) : AnyShapeStyle(AppTheme.Colors.paperCream),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(roastMode ? .dark : .light, for: .navigationBar)
    }
}

extension View {
    func bitBinderToolbar(roastMode: Bool) -> some View {
        modifier(BitBinderToolbar(roastMode: roastMode))
    }
}

// MARK: - Previews

#Preview("Empty State") {
    BitBinderEmptyState(
        icon: "theatermasks.fill",
        title: "No jokes yet",
        subtitle: "Add your first joke using the + button above",
        actionTitle: "Add Joke",
        action: { }
    )
}

#Preview("Chips") {
    VStack(spacing: 16) {
        HStack {
            BitBinderChip(text: "All Jokes", isSelected: true, style: .filter)
            BitBinderChip(text: "Observational", isSelected: false, style: .filter)
            BitBinderChip(text: "One-liners", isSelected: false, style: .filter)
        }
        
        HStack {
            BitBinderChip(text: "dating", icon: "tag.fill", style: .tag)
            BitBinderChip(text: "work", icon: "tag.fill", style: .tag)
        }
    }
    .padding()
    .background(AppTheme.Colors.paperCream)
}

#Preview("Badges") {
    VStack(spacing: 12) {
        HStack {
            BitBinderBadge(text: "Synced", icon: "checkmark.circle.fill", variant: .success)
            BitBinderBadge(text: "Needs Review", icon: "eye.fill", variant: .warning)
            BitBinderBadge(text: "Error", icon: "xmark.circle.fill", variant: .error)
        }
        HStack {
            HitStarBadge()
            ConfidenceBadge(level: .high)
            ConfidenceBadge(level: .medium)
            ConfidenceBadge(level: .low)
        }
    }
    .padding()
    .background(AppTheme.Colors.paperCream)
}
