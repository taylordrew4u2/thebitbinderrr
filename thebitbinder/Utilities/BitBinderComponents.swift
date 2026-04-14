//
//  BitBinderComponents.swift
//  thebitbinder
//
//  Shared UI components following native iOS design patterns.
//

import SwiftUI

// MARK: - Empty State Component (using ContentUnavailableView pattern)

struct BitBinderEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var roastMode: Bool = false
    var iconGradient: LinearGradient? = nil
    
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(subtitle)
        } actions: {
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            }
        }
    }
}

// MARK: - Badge Component

struct BitBinderBadge: View {
    let text: String
    var icon: String? = nil
    var variant: BadgeVariant = .neutral
    var size: BadgeSize = .small
    var roastMode: Bool = false
    
    enum BadgeVariant {
        case neutral, success, warning, error, gold, info
        
        var backgroundColor: Color {
            switch self {
            case .neutral: return Color(UIColor.secondarySystemBackground)
            case .success: return Color.blue.opacity(0.12)
            case .warning: return Color.blue.opacity(0.12)
            case .error: return Color.red.opacity(0.12)
            case .gold: return Color.blue.opacity(0.15)
            case .info: return Color.blue.opacity(0.12)
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .neutral: return .secondary
            case .success: return .blue
            case .warning: return .blue
            case .error: return .red
            case .gold: return .blue
            case .info: return .blue
            }
        }
    }
    
    enum BadgeSize {
        case small, medium
        
        var font: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(size.font.weight(.semibold))
            }
            Text(text)
                .font(size.font.weight(.medium))
        }
        .foregroundColor(variant.foregroundColor)
        .padding(.horizontal, size == .small ? 6 : 8)
        .padding(.vertical, size == .small ? 3 : 4)
        .background(variant.backgroundColor, in: Capsule())
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let level: ConfidenceLevel
    var roastMode: Bool = false
    
    enum ConfidenceLevel: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case review = "Review"
        
        var variant: BitBinderBadge.BadgeVariant {
            switch self {
            case .high: return .success
            case .medium: return .info
            case .low: return .warning
            case .review: return .neutral
            }
        }
        
        var icon: String {
            switch self {
            case .high: return "checkmark.circle.fill"
            case .medium: return "circle.fill"
            case .low: return "exclamationmark.circle.fill"
            case .review: return "eye.fill"
            }
        }
    }
    
    var body: some View {
        BitBinderBadge(
            text: level.rawValue,
            icon: level.icon,
            variant: level.variant,
            size: .small,
            roastMode: roastMode
        )
    }
}

// MARK: - Toolbar Background Modifier (simplified)

struct BitBinderToolbar: ViewModifier {
    var roastMode: Bool = false
    
    func body(content: Content) -> some View {
        content
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
        icon: "text.quote",
        title: "No jokes yet",
        subtitle: "Add your first joke using the + button",
        actionTitle: "Add Joke",
        action: { }
    )
}

#Preview("Badges") {
    VStack(spacing: 12) {
        HStack {
            BitBinderBadge(text: "Synced", icon: "checkmark.circle.fill", variant: .success)
            BitBinderBadge(text: "Review", icon: "eye.fill", variant: .warning)
            BitBinderBadge(text: "Error", icon: "xmark.circle.fill", variant: .error)
        }
        HStack {
            ConfidenceBadge(level: .high)
            ConfidenceBadge(level: .medium)
            ConfidenceBadge(level: .low)
        }
    }
    .padding()
}