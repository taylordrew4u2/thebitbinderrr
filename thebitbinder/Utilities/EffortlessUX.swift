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
// Professional, restrained animations - dependable tool feel, not playful

struct EffortlessAnimation {
    /// Snappy spring - buttons, toggles (well-damped, no bounce)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.85, blendDuration: 0)
    
    /// Quick spring - chips, cards (smooth, professional)
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.88, blendDuration: 0)
    
    /// Smooth spring - sheets, larger elements
    static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.9, blendDuration: 0)
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
                        .tint(roastMode ? .white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("Saving...")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(roastMode ? .white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if autoSave.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("Editing")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(roastMode ? .white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if let lastSave = autoSave.lastSaveTime, Date().timeIntervalSince(lastSave) < 3 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("Saved")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.blue)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(roastMode ? .white : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(roastMode ? Color(UIColor.tertiarySystemBackground) : Color(UIColor.secondarySystemBackground))
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

// MARK: - View Extensions for Effortless UX

extension View {
    /// Success toast overlay
    func successToast(message: String, icon: String = "checkmark.circle.fill", isPresented: Binding<Bool>, roastMode: Bool = false) -> some View {
        self.overlay(alignment: .bottom) {
            SuccessToast(message: message, icon: icon, roastMode: roastMode, isPresented: isPresented)
                .padding(.bottom, 100)
        }
    }
}

// MARK: - Global Haptic Shortcut

/// Convenience enum matching common haptic feedback styles.
enum HapticStyle {
    case light, medium, heavy, soft, rigid
    case success, warning, error
    case selection
}

/// Fire-and-forget haptic feedback.
func haptic(_ style: HapticStyle) {
    switch style {
    case .light:     HapticEngine.shared.tap()
    case .medium:    HapticEngine.shared.press()
    case .heavy:     HapticEngine.shared.impact()
    case .soft:      HapticEngine.shared.soft()
    case .rigid:     HapticEngine.shared.rigid()
    case .success:   HapticEngine.shared.success()
    case .warning:   HapticEngine.shared.warning()
    case .error:     HapticEngine.shared.error()
    case .selection: HapticEngine.shared.selection()
    }
}