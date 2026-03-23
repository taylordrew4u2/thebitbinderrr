//
//  SetListsView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct SetListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var setLists: [SetList]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var showingCreateSetList = false
    @State private var searchText = ""
    @State private var setListToDelete: SetList?
    
    var filteredSetLists: [SetList] {
        if searchText.isEmpty {
            return setLists.sorted { $0.dateModified > $1.dateModified }
        } else {
            return setLists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.dateModified > $1.dateModified }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredSetLists.isEmpty {
                    BitBinderEmptyState(
                        icon: "list.bullet.clipboard.fill",
                        title: roastMode ? "No Roast Sets Yet" : "No Set Lists Yet",
                        subtitle: "Create a set list to organize jokes for your performances",
                        actionTitle: "Create Set List",
                        action: { showingCreateSetList = true },
                        roastMode: roastMode
                    )
                } else {
                    List {
                        ForEach(filteredSetLists) { setList in
                            NavigationLink(value: setList) {
                                SetListRowView(setList: setList)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    setListToDelete = setList
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(roastMode ? "🔥 Roast Sets" : "Set Lists")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SetList.self) { setList in
                SetListDetailView(setList: setList)
            }
            .searchable(text: $searchText, prompt: roastMode ? "Search roast sets" : "Search set lists")
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreateSetList = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSetList) {
                CreateSetListView()
            }
            .alert("Delete Set List?", isPresented: Binding(
                get: { setListToDelete != nil },
                set: { if !$0 { setListToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { setListToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let setList = setListToDelete {
                        modelContext.delete(setList)
                        do {
                            try modelContext.save()
                        } catch {
                            print("❌ [SetListsView] Failed to save after set list deletion: \(error)")
                        }
                        setListToDelete = nil
                    }
                }
            } message: {
                if let setList = setListToDelete {
                    Text(""\(setList.name)" will be permanently deleted. Your jokes will not be affected.")
                }
            }
        }
    }
    
    private func deleteSetLists(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredSetLists[index])
        }
    }
}

struct SetListRowView: View {
    let setList: SetList
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    private var jokeCount: Int {
        roastMode ? setList.roastJokeIDs.count : setList.jokeIDs.count
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(
                        roastMode
                            ? AppTheme.Colors.roastAccent.opacity(0.15)
                            : AppTheme.Colors.primaryAction.opacity(0.1)
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(setList.name)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    // Joke count with icon
                    HStack(spacing: 4) {
                        Image(systemName: roastMode ? "flame.fill" : "text.quote")
                            .font(.system(size: 10))
                        Text("\(jokeCount) \(roastMode ? "roasts" : "jokes")")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent.opacity(0.8) : AppTheme.Colors.primaryAction.opacity(0.8))
                    
                    // Date
                    Text(setList.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 11))
                        .foregroundColor(roastMode ? Color.white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(roastMode ? .white.opacity(0.3) : AppTheme.Colors.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}
