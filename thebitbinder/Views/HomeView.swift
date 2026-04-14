//
//  HomeView.swift
//  thebitbinder
//
//  Home screen - fresh, engaging dashboard.
//  Native iOS design: glanceable, motivating, action-oriented.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - HomeView

struct HomeView: View {
    @Query(filter: #Predicate<Joke> { !$0.isDeleted }) private var allJokes: [Joke]
    @Query(filter: #Predicate<SetList> { !$0.isDeleted }) private var allSets: [SetList]
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isDeleted }) private var allIdeas: [BrainstormIdea]
    @Query(filter: #Predicate<Recording> { !$0.isDeleted }) private var allRecordings: [Recording]

    @State private var showAddJoke = false
    @State private var showTalkToText = false
    @State private var showQuickRecord = false
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("userName") private var userName = ""
    
    // Time-aware greeting
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5:   return "Late night session"
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Night owl mode"
        }
    }
    
    private var greetingName: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return greeting }
        return "\(greeting), \(name)"
    }
    
    // Stats
    private var hitsCount: Int {
        allJokes.filter { $0.isHit }.count
    }
    
    private var thisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allJokes.filter { $0.dateCreated >= weekAgo }.count
    }
    
    private var recentJokes: [Joke] {
        Array(allJokes.sorted(by: { $0.dateModified > $1.dateModified }).prefix(3))
    }

    var body: some View {
        List {
            // MARK: - Greeting Header with BitBuddy
            Section {
                HStack(spacing: 14) {
                    BitBuddyAvatar(roastMode: roastMode, size: 48, symbolSize: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greetingName)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.primary)
                        
                        if allJokes.isEmpty {
                            Text("Let's get your first joke on paper")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text(motivationalSubtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            }
            
            // MARK: - Quick Actions
            Section {
                Button {
                    haptic(.medium)
                    showAddJoke = true
                } label: {
                    Label {
                        Text("New Joke")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.accentColor)
                    }
                }

                Button {
                    haptic(.light)
                    showTalkToText = true
                } label: {
                    Label {
                        Text("Capture Idea")
                    } icon: {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.blue)
                    }
                }

                Button {
                    haptic(.light)
                    showQuickRecord = true
                } label: {
                    Label {
                        Text("Record Set")
                    } icon: {
                        Image(systemName: "record.circle")
                            .foregroundColor(.blue)
                    }
                }
            }

            // MARK: - At a Glance Stats
            Section("At a Glance") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(
                        label: "Jokes",
                        value: allJokes.count,
                        icon: "text.quote",
                        tint: .accentColor
                    )
                    StatCard(
                        label: "Hits",
                        value: hitsCount,
                        icon: "star.fill",
                        tint: .blue
                    )
                    StatCard(
                        label: "Sets",
                        value: allSets.count,
                        icon: "list.bullet.rectangle.portrait",
                        tint: .blue
                    )
                    StatCard(
                        label: "This Week",
                        value: thisWeekCount,
                        icon: "flame.fill",
                        tint: .blue
                    )
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // MARK: - Recent Activity
            if !recentJokes.isEmpty {
                Section("Recent") {
                    ForEach(recentJokes) { joke in
                        NavigationLink(value: joke) {
                            HStack(spacing: 12) {
                                // Hit indicator
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(joke.isHit ? Color.blue : Color(UIColor.separator))
                                    .frame(width: 3, height: 32)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(joke.title.isEmpty ? String(joke.content.prefix(50)) : joke.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 8) {
                                        Text(joke.dateModified.relativeHomeLabel)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if joke.isHit {
                                            Label("Hit", systemImage: "star.fill")
                                                .font(.caption2.weight(.medium))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // MARK: - Ideas & Recordings Summary
            if allIdeas.count > 0 || allRecordings.count > 0 {
                Section("More") {
                    if allIdeas.count > 0 {
                        NavigationLink {
                            BrainstormView()
                                .navigationTitle("Brainstorm")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            LabeledContent {
                                Text("\(allIdeas.count)")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text("Brainstorm Ideas")
                                } icon: {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    
                    if allRecordings.count > 0 {
                        NavigationLink {
                            RecordingsView()
                                .navigationTitle("Recordings")
                                .navigationBarTitleDisplayMode(.large)
                        } label: {
                            LabeledContent {
                                Text("\(allRecordings.count)")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text("Recordings")
                                } icon: {
                                    Image(systemName: "waveform")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Joke.self) { joke in
            JokeDetailView(joke: joke)
        }
        .sheet(isPresented: $showAddJoke) {
            AddJokeView()
        }
        .sheet(isPresented: $showTalkToText) {
            TalkToTextView(selectedFolder: nil as JokeFolder?, saveToBrainstorm: true)
        }
        .sheet(isPresented: $showQuickRecord) {
            StandaloneRecordingView()
        }
    }
    
    private var motivationalSubtitle: String {
        if thisWeekCount > 0 {
            return "\(thisWeekCount) new joke\(thisWeekCount == 1 ? "" : "s") this week — keep it going"
        } else if hitsCount > 0 {
            return "You've got \(hitsCount) hit\(hitsCount == 1 ? "" : "s") in your set"
        } else {
            return "\(allJokes.count) joke\(allJokes.count == 1 ? "" : "s") and counting"
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: Int
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tint)
                Spacer()
            }
            
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToScreen = Notification.Name("navigateToScreen")
}

// MARK: - Date Helper

extension Date {
    var relativeHomeLabel: String {
        let cal = Calendar.current
        let now = Date()
        let diff = cal.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let d = diff.day, d >= 2 {
            return "\(d)d ago"
        } else if let d = diff.day, d == 1 {
            return "Yesterday"
        } else if let h = diff.hour, h >= 1 {
            return "\(h)h ago"
        } else if let m = diff.minute, m >= 1 {
            return "\(m)m ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeView()
            .navigationTitle("Home")
    }
    .modelContainer(for: [
        Joke.self, SetList.self, BrainstormIdea.self,
        Recording.self, ImportBatch.self
    ], inMemory: true)
}