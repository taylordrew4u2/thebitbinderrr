//
//  AIProviderSettingsView.swift
//  thebitbinder
//
//  Settings screen for configuring multiple AI provider API keys.
//  Lets users add keys, reorder providers, and see provider status.
//

import SwiftUI

// MARK: - AI Provider Settings View

struct AIProviderSettingsView: View {
    @State private var providerOrder: [AIProviderType] = AIJokeExtractionManager.shared.providerOrder
    @State private var keys: [AIProviderType: String] = [:]
    @State private var disabledProviders: Set<AIProviderType> = AIJokeExtractionManager.shared.disabledProviders
    @State private var showKeyFor: AIProviderType? = nil
    @State private var editingKey: String = ""
    @State private var showSavedToast = false

    var body: some View {
        List {
            // MARK: - Status Overview
            Section {
                let available = AIJokeExtractionManager.shared.availableProviders
                HStack(spacing: 12) {
                    Image(systemName: available.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundColor(available.isEmpty ? AppTheme.Colors.warning : AppTheme.Colors.success)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(available.isEmpty ? "No AI Providers Active" : "\(available.count) Provider\(available.count == 1 ? "" : "s") Ready")
                            .font(AppTheme.Typography.callout)
                            .foregroundColor(AppTheme.Colors.inkBlack)

                        if available.isEmpty {
                            Text("Add at least one API key to enable smart joke import")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        } else {
                            Text("Fallback order: " + available.map(\.displayName).joined(separator: " → "))
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("GagGrabber AI Status")
            } footer: {
                Text("When one provider hits its rate limit, GagGrabber automatically tries the next one in line. Drag to reorder priority.")
            }

            // MARK: - Provider List (reorderable)
            Section {
                ForEach(providerOrder, id: \.self) { provider in
                    providerRow(provider)
                }
                .onMove { indices, newOffset in
                    providerOrder.move(fromOffsets: indices, toOffset: newOffset)
                    AIJokeExtractionManager.shared.providerOrder = providerOrder
                }
            } header: {
                Text("AI Providers")
            } footer: {
                Text("Each provider has a free tier. Add multiple keys so if one runs out, the next kicks in automatically.")
            }

            // MARK: - How It Works
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "1.circle.fill", text: "Import a file with jokes")
                    infoRow(icon: "2.circle.fill", text: "GagGrabber tries your #1 AI provider")
                    infoRow(icon: "3.circle.fill", text: "Rate limited? Tries provider #2, then #3…")
                    infoRow(icon: "4.circle.fill", text: "All AI providers down? Falls back to local extraction")
                }
                .padding(.vertical, 4)
            } header: {
                Text("How Fallback Works")
            }
        }
        .navigationTitle("AI API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active)) // Enable drag handles
        .onAppear { loadKeys() }
        .sheet(item: $showKeyFor) { provider in
            apiKeyEntrySheet(for: provider)
        }
        .overlay {
            if showSavedToast {
                VStack {
                    Spacer()
                    Text("Key saved!")
                        .font(AppTheme.Typography.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.Colors.success))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 40)
                }
                .animation(.spring(duration: 0.3), value: showSavedToast)
            }
        }
    }

    // MARK: - Provider Row

    private func providerRow(_ provider: AIProviderType) -> some View {
        let hasKey = AIKeyLoader.loadKey(for: provider) != nil
        let isEnabled = !disabledProviders.contains(provider)

        return HStack(spacing: 12) {
            // Provider icon
            Image(systemName: provider.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(hasKey ? AppTheme.Colors.primaryAction : AppTheme.Colors.textTertiary)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.displayName)
                        .font(AppTheme.Typography.callout)
                        .foregroundColor(AppTheme.Colors.inkBlack)

                    if hasKey {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.success)
                    }
                }

                Text(hasKey ? "API key configured" : "No API key")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(hasKey ? AppTheme.Colors.textSecondary : AppTheme.Colors.textTertiary)
            }

            Spacer()

            // Enable/disable toggle (only if key exists)
            if hasKey {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        AIJokeExtractionManager.shared.setProvider(provider, enabled: newValue)
                        disabledProviders = AIJokeExtractionManager.shared.disabledProviders
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.Colors.primaryAction)
            }

            // Configure button
            Button {
                editingKey = AIKeyLoader.loadKey(for: provider) ?? ""
                showKeyFor = provider
            } label: {
                Image(systemName: hasKey ? "key.fill" : "plus.circle")
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - API Key Entry Sheet

    private func apiKeyEntrySheet(for provider: AIProviderType) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Provider header
                VStack(spacing: 8) {
                    Image(systemName: provider.icon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(AppTheme.Colors.primaryAction)

                    Text(provider.displayName)
                        .font(AppTheme.Typography.title2)
                        .foregroundColor(AppTheme.Colors.inkBlack)

                    Text("Model: \(provider.defaultModel)")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .padding(.top, 20)

                // Key input
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundColor(AppTheme.Colors.textSecondary)

                    SecureField("Paste your API key here", text: $editingKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal)

                // Get key link
                Link(destination: provider.keySignupURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Get a free \(provider.displayName) API key")
                    }
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.Colors.primaryAction)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Save button
                    Button {
                        AIKeyLoader.saveKey(editingKey, for: provider)
                        loadKeys()
                        showKeyFor = nil
                        withAnimation { showSavedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showSavedToast = false }
                        }
                    } label: {
                        Text("Save Key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                    .fill(AppTheme.Colors.primaryAction)
                            )
                    }

                    // Remove key button (only if key exists)
                    if AIKeyLoader.loadKey(for: provider) != nil {
                        Button(role: .destructive) {
                            AIKeyLoader.clearKey(for: provider)
                            editingKey = ""
                            loadKeys()
                            showKeyFor = nil
                        } label: {
                            Text("Remove Key")
                                .font(AppTheme.Typography.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showKeyFor = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Info Row

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .frame(width: 24)

            Text(text)
                .font(AppTheme.Typography.subheadline)
                .foregroundColor(AppTheme.Colors.textPrimary)
        }
    }

    // MARK: - Helpers

    private func loadKeys() {
        keys = Dictionary(uniqueKeysWithValues: AIProviderType.allCases.map { provider in
            (provider, AIKeyLoader.loadKey(for: provider) ?? "")
        })
        providerOrder = AIJokeExtractionManager.shared.providerOrder
        disabledProviders = AIJokeExtractionManager.shared.disabledProviders
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AIProviderSettingsView()
    }
}
