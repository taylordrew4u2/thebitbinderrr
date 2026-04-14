//
//  ContentView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    var body: some View {
        MainTabView()
            .preferredColorScheme(roastMode ? .dark : nil)
    }
}

// MARK: - App Screens

enum AppScreen: String, CaseIterable {
    case home = "Home"
    case brainstorm = "Brainstorm"
    case jokes = "Jokes"
    case sets = "Sets"
    case recordings = "Recordings"
    case notebookSaver = "Notebook"
    case settings = "Settings"

    static var roastScreens: [AppScreen] {
        [.jokes, .settings]
    }
    
    // Screens visible in the tab bar (primary navigation)
    static var tabBarScreens: [AppScreen] {
        [.home, .jokes, .sets, .notebookSaver, .settings]
    }
    
    static var roastTabBarScreens: [AppScreen] {
        [.jokes, .settings]
    }

    var icon: String {
        switch self {
        case .home:          return "house"
        case .brainstorm:    return "lightbulb"
        case .jokes:         return "text.quote"
        case .sets:          return "list.bullet.rectangle.portrait"
        case .recordings:    return "waveform"
        case .notebookSaver: return "book.closed"
        case .settings:      return "gearshape"
        }
    }
    
    var selectedIcon: String {
        switch self {
        case .home:          return "house.fill"
        case .brainstorm:    return "lightbulb.fill"
        case .jokes:         return "text.quote"
        case .sets:          return "list.bullet.rectangle.portrait.fill"
        case .recordings:    return "waveform"
        case .notebookSaver: return "book.closed.fill"
        case .settings:      return "gearshape.fill"
        }
    }

    var roastName: String {
        switch self {
        case .home:          return "Home"
        case .brainstorm:    return "Ideas"
        case .jokes:         return "Roasts"
        case .sets:          return "Roast Sets"
        case .recordings:    return "Recordings"
        case .notebookSaver: return "Notebook"
        case .settings:      return "Settings"
        }
    }

    var roastIcon: String {
        switch self {
        case .jokes:         return "flame"
        default:             return icon
        }
    }
    
    var roastSelectedIcon: String {
        switch self {
        case .jokes:         return "flame.fill"
        default:             return selectedIcon
        }
    }

    var color: Color {
        // Use system accent color for consistency
        return .accentColor
    }

    var roastColor: Color {
        switch self {
        case .jokes:         return .blue
        default:             return .accentColor
        }
    }
    
    /// Content-heavy screens with VStack wrappers use `.inline` so the
    /// title bar doesn't eat vertical space that can't be reclaimed by
    /// scroll-collapse. Dashboard and list screens keep `.large`.
    var preferredTitleDisplayMode: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .home, .settings, .sets, .notebookSaver, .recordings:
            return .large
        case .jokes, .brainstorm:
            return .inline
        }
    }
}

// MARK: - Main Tab View (Standard iOS TabView)

struct MainTabView: View {
    // Persist the selected tab across app launches
    @AppStorage("selectedTabRawValue") private var selectedTabRaw: String = AppScreen.home.rawValue
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State private var showAIChat = false
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    // Computed binding for the selected tab
    private var selectedTab: Binding<AppScreen> {
        Binding(
            get: {
                // On first launch, always show Home
                if !hasLaunchedBefore {
                    return .home
                }
                // Otherwise, restore the saved tab (if valid for current mode)
                if let tab = AppScreen(rawValue: selectedTabRaw), visibleTabs.contains(tab) {
                    return tab
                }
                return roastMode ? .jokes : .home
            },
            set: { newTab in
                selectedTabRaw = newTab.rawValue
            }
        )
    }
    
    private var visibleTabs: [AppScreen] {
        roastMode ? AppScreen.roastTabBarScreens : AppScreen.tabBarScreens
    }
    
    var body: some View {
        TabView(selection: selectedTab) {
            ForEach(visibleTabs, id: \.self) { screen in
                NavigationStack {
                    screenView(for: screen)
                        .navigationTitle(screen == .home ? "" : (roastMode ? screen.roastName : screen.rawValue))
                        .navigationBarTitleDisplayMode(screen == .home ? .inline : screen.preferredTitleDisplayMode)
                        .toolbar {
                            // AI Chat button in toolbar (subtle, not a FAB)
                            if screen == .home || screen == .jokes {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button {
                                        showAIChat = true
                                    } label: {
                                        Image(systemName: "bubble.left.and.bubble.right")
                                            .symbolRenderingMode(.hierarchical)
                                    }
                                }
                            }
                        }
                }
                .tabItem {
                    Label(
                        roastMode ? screen.roastName : screen.rawValue,
                        systemImage: selectedTab.wrappedValue == screen
                            ? (roastMode ? screen.roastSelectedIcon : screen.selectedIcon)
                            : (roastMode ? screen.roastIcon : screen.icon)
                    )
                }
                .tag(screen)
            }
        }
        .tint(.blue)
        .onAppear {
            // Mark first launch complete after showing Home
            if !hasLaunchedBefore {
                // Small delay to ensure Home is shown first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    hasLaunchedBefore = true
                }
            }
        }
        .onChange(of: roastMode) { _, isRoast in
            haptic(.medium)
            // Redirect to valid tab when mode changes
            if isRoast && !AppScreen.roastTabBarScreens.contains(selectedTab.wrappedValue) {
                selectedTabRaw = AppScreen.jokes.rawValue
            } else if !isRoast && !AppScreen.tabBarScreens.contains(selectedTab.wrappedValue) {
                selectedTabRaw = AppScreen.home.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToScreen)) { notification in
            if let screenRaw = notification.userInfo?["screen"] as? String,
               let screen = AppScreen(rawValue: screenRaw) {
                if visibleTabs.contains(screen) {
                    selectedTabRaw = screen.rawValue
                }
            }
        }
        .sheet(isPresented: $showAIChat) {
            NavigationStack {
                BitBuddyChatView()
            }
        }
    }
    
    @ViewBuilder
    private func screenView(for screen: AppScreen) -> some View {
        switch screen {
        case .home:
            HomeView()
        case .brainstorm:
            BrainstormView()
        case .jokes:
            JokesView()
        case .sets:
            SetListsView()
        case .recordings:
            RecordingsView()
        case .notebookSaver:
            NotebookView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Joke.self, inMemory: true)
}