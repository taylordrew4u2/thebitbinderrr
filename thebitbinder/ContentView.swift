//
//  ContentView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var showLaunchScreen = true
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    var body: some View {
        ZStack {
            MainTabView()
            
            if showLaunchScreen {
                LaunchScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Flip the whole app color scheme based on roast mode
        .preferredColorScheme(roastMode ? .dark : .light)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showLaunchScreen = false
                }
            }
        }
    }
}

// MARK: - App Screens

enum AppScreen: String, CaseIterable {
    case home = "Home"
    case brainstorm = "Brainstorm"
    case jokes = "Jokes"
    case sets = "Set Lists"
    case recordings = "Recordings"
    case notebookSaver = "Notebook"
    case settings = "Settings"

    // The screens visible in roast mode (in order) - only roasts (targets) and settings
    static var roastScreens: [AppScreen] {
        [.jokes, .settings]
    }

    var icon: String {
        switch self {
        case .home:          return "house.fill"
        case .brainstorm:    return "lightbulb.fill"
        case .jokes:         return "theatermask.and.paintbrush.fill"
        case .sets:          return "list.bullet.rectangle.portrait.fill"
        case .recordings:    return "waveform.circle.fill"
        case .notebookSaver: return "book.closed.fill"
        case .settings:      return "gearshape.fill"
        }
    }

    // Roast-mode display name
    var roastName: String {
        switch self {
        case .home:          return "Fire Home"
        case .brainstorm:    return "Fire Ideas"
        case .jokes:         return "Roasts"
        case .sets:          return "Roast Sets"
        case .recordings:    return "Burn Recordings"
        case .notebookSaver: return "Fire Notebook"
        case .settings:      return "Settings"
        }
    }

    // Roast-mode icon
    var roastIcon: String {
        switch self {
        case .home:          return "flame.fill"
        case .brainstorm:    return "flame.circle.fill"
        case .jokes:         return "flame.circle.fill"
        case .sets:          return "list.bullet.rectangle.portrait.fill"
        case .recordings:    return "waveform.circle.fill"
        case .notebookSaver: return "book.closed.fill"
        case .settings:      return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .home:          return AppTheme.Colors.primaryAction
        case .brainstorm:    return AppTheme.Colors.brainstormAccent
        case .jokes:         return AppTheme.Colors.jokesAccent
        case .sets:          return AppTheme.Colors.setsAccent
        case .recordings:    return AppTheme.Colors.recordingsAccent
        case .notebookSaver: return AppTheme.Colors.notebookAccent
        case .settings:      return AppTheme.Colors.settingsAccent
        }
    }

    // Roast-mode accent (all ember/fire tones)
    var roastColor: Color {
        switch self {
        case .home:          return AppTheme.Colors.roastAccent
        case .brainstorm:    return Color(red: 1.0, green: 0.65, blue: 0.08)
        case .jokes:         return AppTheme.Colors.roastAccent
        case .sets:          return Color(red: 1.0, green: 0.55, blue: 0.10)
        case .recordings:    return Color(red: 0.95, green: 0.35, blue: 0.10)
        case .notebookSaver: return Color(red: 0.90, green: 0.45, blue: 0.10)
        case .settings:      return Color(red: 0.65, green: 0.55, blue: 0.50)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @State private var selectedScreen: AppScreen = .home
    @State private var screenHistory: [AppScreen] = []
    @State private var showMenu = false
    @State private var showAIChat = false
    @AppStorage("roastModeEnabled") private var roastMode = false

    // Track the screen user was on before entering roast mode so we can restore it
    @State private var preRoastScreen: AppScreen? = nil

    private var canGoBack: Bool { !screenHistory.isEmpty }

    private func navigate(to screen: AppScreen) {
        guard screen != selectedScreen else { return }
        
        // In roast mode, only allow navigation to roast screens
        if roastMode && !AppScreen.roastScreens.contains(screen) {
            return
        }
        
        screenHistory.append(selectedScreen)
        selectedScreen = screen
    }

    private func goBack() {
        guard let previous = screenHistory.popLast() else { return }
        // In roast mode, skip non-roast screens in history
        if roastMode && !AppScreen.roastScreens.contains(previous) {
            // Try to go back further, or stay on current screen
            goBack()
            return
        }
        selectedScreen = previous
    }

    // When roast mode turns on, jump to Roasts; when off, restore previous screen
    private func handleRoastModeChange(isRoast: Bool) {
        if isRoast {
            // Save the current screen so we can restore it when roast mode is turned off
            preRoastScreen = selectedScreen
            screenHistory.removeAll()
            selectedScreen = .jokes // Always start with roasts in roast mode
        } else {
            screenHistory.removeAll()
            // Restore the screen the user was on before roast mode, or default to notepad
            if let restored = preRoastScreen, !AppScreen.roastScreens.contains(restored) || restored == .settings {
                selectedScreen = restored
            } else {
                selectedScreen = .home
            }
            preRoastScreen = nil
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Background — charcoal in roast mode, paper in normal
            (roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.surface)
                .ignoresSafeArea()

            // Main content
            Group {
                // In roast mode, only allow roast screens
                if roastMode && !AppScreen.roastScreens.contains(selectedScreen) {
                    // Force to roasts if somehow we're on a non-roast screen
                    EmptyView()
                        .onAppear {
                            selectedScreen = .jokes
                        }
                } else {
                    switch selectedScreen {
                    case .home:
                        if roastMode {
                            // Roast mode should never show home - redirect to roasts
                            EmptyView()
                                .onAppear {
                                    selectedScreen = .jokes
                                }
                        } else {
                            HomeView()
                        }
                    case .brainstorm:    BrainstormView()
                    case .jokes:         JokesView()
                    case .sets:          SetListsView()
                    case .recordings:    RecordingsView()
                    case .notebookSaver: NotebookView()
                    case .settings:      SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Dim overlay when menu is open
            if showMenu {
                Color.black.opacity(roastMode ? 0.65 : 0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeOut(duration: 0.2)) {
                            showMenu = false
                        }
                    }
                    .transition(.opacity)
            }

            // Side menu
            if showMenu {
                ModernSideMenu(selectedScreen: $selectedScreen, showMenu: $showMenu, showAIChat: $showAIChat, onNavigate: { navigate(to: $0) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            // Floating FABs — back button on left, menu on right
            if !showMenu {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .overlay(alignment: .topLeading) {
                        if canGoBack {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    goBack()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(roastMode
                                            ? Color.white.opacity(0.12)
                                            : AppTheme.Colors.inkBlack.opacity(0.08))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                                }
                            }
                            .buttonStyle(FABButtonStyle())
                            .transition(.scale.combined(with: .opacity))
                            .padding(.leading, 20)
                            .padding(.top, 56)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            dismissKeyboard()
                            withAnimation(.easeOut(duration: 0.25)) {
                                showMenu = true
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(roastMode ? AppTheme.Colors.roastEmberGradient : AppTheme.Colors.leatherGradient)
                                    .frame(width: 46, height: 46)
                                Image(systemName: roastMode ? "flame.fill" : "book.closed.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .shadow(
                                color: (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.notebookAccent).opacity(0.40),
                                radius: 10, y: 4
                            )
                        }
                        .buttonStyle(FABButtonStyle())
                        .padding(.trailing, 20)
                        .padding(.top, 56)
                    }
            }
        }
        .onChange(of: roastMode) { _, newValue in
            handleRoastModeChange(isRoast: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToScreen)) { notification in
            if let screenRaw = notification.userInfo?["screen"] as? String,
               let screen = AppScreen(rawValue: screenRaw) {
                navigate(to: screen)
            }
        }
        .onAppear {
            // Fix initial screen selection if roast mode is already enabled
            if roastMode && !AppScreen.roastScreens.contains(selectedScreen) {
                selectedScreen = .jokes
            }
        }
        .sheet(isPresented: $showAIChat) {
            NavigationStack {
                BitBuddyChatView()
            }
        }
    }
}

// MARK: - Side Menu

struct ModernSideMenu: View {
    @Binding var selectedScreen: AppScreen
    @Binding var showMenu: Bool
    @Binding var showAIChat: Bool
    var onNavigate: (AppScreen) -> Void
    @AppStorage("roastModeEnabled") private var roastMode = false

    private var visibleScreens: [AppScreen] {
        roastMode ? AppScreen.roastScreens : AppScreen.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            menuHeader

            // Items
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(visibleScreens, id: \.self) { screen in
                        ModernMenuItem(screen: screen, isSelected: selectedScreen == screen) {
                            onNavigate(screen)
                            withAnimation(.easeOut(duration: 0.2)) {
                                showMenu = false
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // BitBuddy Chat
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showMenu = false
                        }
                        // Small delay so menu closes before sheet opens
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showAIChat = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                                .frame(width: 24)
                            
                            Text("BitBuddy")
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .foregroundColor(roastMode ? Color.white.opacity(0.60) : AppTheme.Colors.textSecondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(Color.clear)
                        )
                    }
                    .buttonStyle(MenuItemStyle(isSelected: false))
                }
                .padding(16)
            }

            Spacer()

            // Footer
            HStack(spacing: 4) {
                Image(systemName: roastMode ? "flame" : "pencil.and.scribble")
                    .font(.caption2)
                Text("v9.4")
                    .font(.system(size: 11, design: .serif))
            }
            .foregroundStyle(roastMode ? Color.orange.opacity(0.5) : AppTheme.Colors.textTertiary)
            .padding(.bottom, 24)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(
            (roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.surface)
                .shadow(color: .black.opacity(roastMode ? 0.5 : 0.3), radius: 20, x: -10, y: 0)
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var menuHeader: some View {
        if roastMode {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        dismissKeyboard()
                        withAnimation(.easeOut(duration: 0.2)) { showMenu = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(FABButtonStyle())
                }

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Colors.roastAccent.opacity(0.20))
                            .frame(width: 54, height: 54)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.roastEmberGradient)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RoastBinder")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text("turn up the heat")
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundColor(AppTheme.Colors.roastAccent.opacity(0.75))
                            .italic()
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(AppTheme.Colors.roastHeaderGradient)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        dismissKeyboard()
                        withAnimation(.easeOut(duration: 0.2)) { showMenu = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(FABButtonStyle())
                }

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 54, height: 54)
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("BitBinder")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text("shut up and write some jokes")
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundColor(.white.opacity(0.60))
                            .italic()
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(AppTheme.Colors.leatherGradient)
        }
    }
}

// MARK: - Menu Item

struct ModernMenuItem: View {
    let screen: AppScreen
    let isSelected: Bool
    let action: () -> Void
    @AppStorage("roastModeEnabled") private var roastMode = false

    private var label: String   { roastMode ? screen.roastName  : screen.rawValue }
    private var icon: String    { roastMode ? screen.roastIcon  : screen.icon }
    // Use unified primary action for selected, per-screen accent for icon only
    private var iconAccent: Color { roastMode ? screen.roastColor : screen.color }
    private var selectedAccent: Color { roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? selectedAccent : iconAccent)
                    .frame(width: 24)

                Text(label)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular, design: .serif))
                    .foregroundColor(isSelected
                        ? (roastMode ? .white : AppTheme.Colors.inkBlack)
                        : (roastMode ? Color.white.opacity(0.60) : AppTheme.Colors.textSecondary))

                Spacer()

                if isSelected {
                    Circle()
                        .fill(selectedAccent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(isSelected
                        ? selectedAccent.opacity(roastMode ? 0.15 : 0.10)
                        : Color.clear)
            )
        }
        .buttonStyle(MenuItemStyle(isSelected: isSelected))
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Joke.self, inMemory: true)
}
