//
//  EffortlessUX.swift
//  thebitbinder
//
//  Smooth animations, haptics, auto-save, and effortless interactions
//  Everything should feel natural and responsive.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Haptic Engine

/// Centralized haptic feedback - feel every action
final class HapticEngine {
    static let shared = HapticEngine()
    
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        // Pre-warm generators for instant response
        prepareAll()
    }
    
    func prepareAll() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    // MARK: - Core Haptics
    
    /// Light tap - selections, toggles, chip taps
    func tap() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }
    
    /// Medium tap - button presses, confirmations
    func press() {
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }
    
    /// Heavy tap - major actions, deletions
    func impact() {
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
    }
    
    /// Soft tap - subtle feedback, scrolling stops
    func soft() {
        softGenerator.impactOccurred()
        softGenerator.prepare()
    }
    
    /// Rigid tap - precise, mechanical feedback
    func rigid() {
        rigidGenerator.impactOccurred()
        rigidGenerator.prepare()
    }
    
    /// Selection change - picker changes, segment controls
    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
    
    // MARK: - Notification Haptics
    
    /// Success - save completed, sync done
    func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }
    
    /// Warning - needs attention, unsaved changes
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }
    
    /// Error - failed action, conflict
    func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
    
    // MARK: - Composite Haptics
    
    /// Double tap - emphasize important actions
    func doubleTap() {
        lightGenerator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.lightGenerator.impactOccurred()
            self.lightGenerator.prepare()
        }
    }
    
    /// Star toggle - The Hits marking
    func starToggle(_ isOn: Bool) {
        if isOn {
            mediumGenerator.impactOccurred(intensity: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.lightGenerator.impactOccurred(intensity: 0.6)
            }
        } else {
            lightGenerator.impactOccurred(intensity: 0.4)
        }
        lightGenerator.prepare()
    }
    
    /// Delete haptic - swipe to delete
    func delete() {
        rigidGenerator.impactOccurred(intensity: 0.9)
        rigidGenerator.prepare()
    }
    
    /// Save haptic - content saved
    func save() {
        softGenerator.impactOccurred(intensity: 0.7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.success()
        }
    }
}

// MARK: - Effortless Animations

struct EffortlessAnimation {
    /// Snappy spring - buttons, toggles
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)
    
    /// Quick spring - chips, cards
    static let quick = Animation.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0)
    
    /// Smooth spring - sheets, larger elements
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0)
    
    /// Gentle spring - subtle feedback
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.9, blendDuration: 0)
    
    /// Bouncy spring - FABs, celebration
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)
    
    /// Ultra fast - instant feedback
    static let instant = Animation.easeOut(duration: 0.1)
    
    /// Ease out - slide animations
    static let slideOut = Animation.easeOut(duration: 0.25)
    
    /// Ease in-out - transitions
    static let transition = Animation.easeInOut(duration: 0.3)
}

// MARK: - Auto-Save Manager

/// Automatic saving with debouncing - never lose work
final class AutoSaveManager: ObservableObject {
    static let shared = AutoSaveManager()
    
    @Published var isSaving = false
    @Published var lastSaveTime: Date?
    @Published var hasUnsavedChanges = false
    
    private var saveSubject = PassthroughSubject<() -> Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Debounce saves by 1.5 seconds
        saveSubject
            .debounce(for: .milliseconds(1500), scheduler: DispatchQueue.main)
            .sink { [weak self] saveAction in
                self?.performSave(saveAction)
            }
            .store(in: &cancellables)
    }
    
    /// Schedule a save operation (debounced)
    func scheduleSave(_ action: @escaping () -> Void) {
        hasUnsavedChanges = true
        saveSubject.send(action)
    }
    
    /// Force an immediate save
    func saveNow(_ action: @escaping () -> Void) {
        performSave(action)
    }
    
    private func performSave(_ action: () -> Void) {
        isSaving = true
        action()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isSaving = false
            self.hasUnsavedChanges = false
            self.lastSaveTime = Date()
        }
    }
}

// MARK: - Save Status Indicator

/// Subtle auto-save status indicator
struct SaveStatusIndicator: View {
    @ObservedObject var autoSave: AutoSaveManager = .shared
    var roastMode: Bool = false
    
    var body: some View {
        Group {
            if autoSave.isSaving {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    Text("Saving...")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if autoSave.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.Colors.warning)
                        .frame(width: 6, height: 6)
                    Text("Editing")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if let lastSave = autoSave.lastSaveTime, Date().timeIntervalSince(lastSave) < 3 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.success)
                    Text("Saved")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(AppTheme.Colors.success)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(EffortlessAnimation.quick, value: autoSave.isSaving)
        .animation(EffortlessAnimation.quick, value: autoSave.hasUnsavedChanges)
    }
}

// MARK: - Success Toast

struct SuccessToast: View {
    let message: String
    let icon: String
    var roastMode: Bool = false
    @Binding var isPresented: Bool
    
    var body: some View {
        if isPresented {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.success)
                
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: 20)),
                removal: .opacity.combined(with: .offset(y: -10))
            ))
            .onAppear {
                HapticEngine.shared.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(EffortlessAnimation.smooth) {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String
    var roastMode: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.textPrimary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            )
        }
        .transition(.opacity)
    }
}

// MARK: - Swipe Action Modifier

struct SwipeActionModifier: ViewModifier {
    let leadingActions: [SwipeAction]
    let trailingActions: [SwipeAction]
    
    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    
    struct SwipeAction {
        let icon: String
        let color: Color
        let action: () -> Void
    }
    
    func body(content: Content) -> some View {
        ZStack {
            // Leading actions background
            HStack {
                ForEach(Array(leadingActions.enumerated()), id: \.offset) { _, action in
                    Button {
                        withAnimation(EffortlessAnimation.snappy) {
                            offset = 0
                        }
                        HapticEngine.shared.tap()
                        action.action()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: .infinity)
                            .background(action.color)
                    }
                }
                Spacer()
            }
            
            // Trailing actions background
            HStack {
                Spacer()
                ForEach(Array(trailingActions.reversed().enumerated()), id: \.offset) { _, action in
                    Button {
                        withAnimation(EffortlessAnimation.snappy) {
                            offset = 0
                        }
                        HapticEngine.shared.tap()
                        action.action()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: .infinity)
                            .background(action.color)
                    }
                }
            }
            
            // Main content
            content
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = startOffset + value.translation.width
                            
                            // Rubber band effect at edges
                            if newOffset > 0 && leadingActions.isEmpty {
                                offset = rubberBand(newOffset, limit: 30)
                            } else if newOffset < 0 && trailingActions.isEmpty {
                                offset = rubberBand(newOffset, limit: 30)
                            } else {
                                offset = newOffset.clamped(to: -CGFloat(trailingActions.count) * 70...CGFloat(leadingActions.count) * 70)
                            }
                        }
                        .onEnded { value in
                            startOffset = 0
                            _ = value.predictedEndLocation.x - value.location.x
                            
                            withAnimation(EffortlessAnimation.snappy) {
                                // Snap to action positions or back to zero
                                if offset > 50 && !leadingActions.isEmpty {
                                    offset = CGFloat(leadingActions.count) * 60
                                    HapticEngine.shared.selection()
                                } else if offset < -50 && !trailingActions.isEmpty {
                                    offset = -CGFloat(trailingActions.count) * 60
                                    HapticEngine.shared.selection()
                                } else {
                                    offset = 0
                                }
                            }
                        }
                )
        }
    }
    
    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        let absValue = abs(value)
        return sign * limit * (1 - exp(-absValue / limit))
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Keyboard Shortcuts

struct KeyboardShortcuts: ViewModifier {
    let onSave: () -> Void
    let onNew: (() -> Void)?
    let onSearch: (() -> Void)?
    let onDelete: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            // iOS doesn't support keyboard shortcuts the same way as macOS
            // but we can add them for external keyboards
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // Keyboard handling can be added here if needed
            }
    }
}

// MARK: - View Extensions for Effortless UX

extension View {
    /// Apply snappy spring animation
    func snappyAnimation<V: Equatable>(value: V) -> some View {
        self.animation(EffortlessAnimation.snappy, value: value)
    }
    
    /// Apply smooth spring animation
    func smoothAnimation<V: Equatable>(value: V) -> some View {
        self.animation(EffortlessAnimation.smooth, value: value)
    }
    
    /// Apply bouncy spring animation
    func bouncyAnimation<V: Equatable>(value: V) -> some View {
        self.animation(EffortlessAnimation.bouncy, value: value)
    }
    
    /// Haptic tap on action
    func hapticTap(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: style)
                    generator.impactOccurred()
                }
        )
    }
    
    /// Success toast overlay
    func successToast(message: String, icon: String = "checkmark.circle.fill", isPresented: Binding<Bool>, roastMode: Bool = false) -> some View {
        self.overlay(alignment: .bottom) {
            SuccessToast(message: message, icon: icon, roastMode: roastMode, isPresented: isPresented)
                .padding(.bottom, 100)
        }
    }
    
    /// Loading overlay
    func loadingOverlay(message: String = "Loading...", isLoading: Bool, roastMode: Bool = false) -> some View {
        self.overlay {
            if isLoading {
                LoadingOverlay(message: message, roastMode: roastMode)
            }
        }
    }
    
    /// Shimmer loading effect
    func shimmer(isActive: Bool = true) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.4),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase)
                    .mask(content)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 200
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Smooth Scale Button Style

/// Enhanced button style with smooth scaling and optional haptic
struct SmoothScaleButtonStyle: ButtonStyle {
    let scale: CGFloat
    let haptic: Bool
    
    init(scale: CGFloat = 0.96, haptic: Bool = true) {
        self.scale = scale
        self.haptic = haptic
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(EffortlessAnimation.instant, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic {
                    HapticEngine.shared.tap()
                }
            }
    }
}

// MARK: - Pull to Refresh Haptic

struct PullToRefreshHaptic: ViewModifier {
    @Binding var isRefreshing: Bool
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isRefreshing) { _, newValue in
                if newValue {
                    HapticEngine.shared.soft()
                } else {
                    HapticEngine.shared.success()
                }
            }
    }
}

// MARK: - Gesture State Indicator

/// Visual indicator for swipe gesture state
struct SwipeIndicator: View {
    let direction: SwipeDirection
    let progress: CGFloat
    var roastMode: Bool = false
    
    enum SwipeDirection {
        case left, right
    }
    
    var body: some View {
        HStack {
            if direction == .right { Spacer() }
            
            Circle()
                .fill(
                    direction == .left
                        ? AppTheme.Colors.success.opacity(Double(progress))
                        : AppTheme.Colors.error.opacity(Double(progress))
                )
                .frame(width: 8, height: 8)
                .scaleEffect(0.5 + progress * 0.5)
            
            if direction == .left { Spacer() }
        }
        .opacity(progress > 0.1 ? 1 : 0)
        .animation(EffortlessAnimation.instant, value: progress)
    }
}
