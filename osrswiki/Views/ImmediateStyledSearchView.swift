//
//  ImmediateStyledSearchView.swift
//  OSRS Wiki
//
//  Immediate focus with proper OSRS Wiki styling
//

import SwiftUI
import UIKit

// UIKit TextField with immediate focus and proper styling
struct ImmediateStyledTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let theme: any osrsThemeProtocol
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ImmediateStyledTextField
        
        init(_ parent: ImmediateStyledTextField) {
            self.parent = parent
        }
        
        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .search
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.textColor = UIColor(theme.primaryTextColor)
        textField.tintColor = UIColor(theme.primary)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        
        // FORCE IMMEDIATE FOCUS
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        
        // Keep focus on first appearance
        if uiView.window != nil && !uiView.isFirstResponder && text.isEmpty {
            uiView.becomeFirstResponder()
        }
    }
}

struct ImmediateStyledSearchView: View {
    @State private var searchText = ""
    @State private var viewModel: SearchViewModel?
    @State private var hasInitialized = false
    
    let appState: AppState
    let themeManager: osrsThemeManager
    let theme: any osrsThemeProtocol
    let customNavigationClosure: ((String, URL, String?, URL?) -> Void)?
    
    // Convenience initializer for backwards compatibility (default navigation)
    init(appState: AppState, themeManager: osrsThemeManager, theme: any osrsThemeProtocol) {
        self.appState = appState
        self.themeManager = themeManager
        self.theme = theme
        self.customNavigationClosure = nil
    }
    
    // Full initializer with custom navigation closure
    init(appState: AppState, themeManager: osrsThemeManager, theme: any osrsThemeProtocol, customNavigationClosure: ((String, URL, String?, URL?) -> Void)?) {
        self.appState = appState
        self.themeManager = themeManager
        self.theme = theme
        self.customNavigationClosure = customNavigationClosure
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search input section at the very top
            searchInputSection
            
            // Content section below - always fill remaining space
            Group {
                if let vm = viewModel {
                    SearchContentSection(
                        viewModel: vm,
                        searchText: $searchText,
                        theme: theme,
                        appState: appState
                    )
                } else if !searchText.isEmpty {
                    // Show loading while view model initializes
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(theme.primary)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptySearchState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(theme.background))
        .ignoresSafeArea(.keyboard)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color(theme.primary))
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            
            // Initialize view model after keyboard shows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak appState, customNavigationClosure] in
                guard let appState = appState else { return }
                
                // DEBUG: Log which navigation context this view is in
                let timestamp = DateFormatter.timeFormatter.string(from: Date())
                print("🔍 [\(timestamp)] IMMEDIATESTYLED: Setting up SearchViewModel with customNavigationClosure: \(customNavigationClosure != nil ? "✅ YES" : "❌ NO")")
                
                let vm = SearchViewModel()
                vm.navigateToArticle = { [weak appState, customNavigationClosure] title, url, searchResult in
                    // DEBUG: Track which navigation path is taken
                    let navTimestamp = DateFormatter.timeFormatter.string(from: Date())
                    let frameId = String(format: "%.3f", Date().timeIntervalSince1970)
                    print("🔍 [\(navTimestamp)] [FRAME:\(frameId)] IMMEDIATESTYLED: navigateToArticle closure called for '\(title)'")
                    
                    // Dismiss keyboard first
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    
                    // Use custom navigation closure if provided, otherwise use default navigation
                    if let customNavigationClosure = customNavigationClosure {
                        // Custom navigation (e.g., for history context)
                        print("🟢 [\(navTimestamp)] [FRAME:\(frameId)] IMMEDIATESTYLED: ✅✅✅ Using CUSTOM navigation closure (history context) ✅✅✅")
                        let snippet = searchResult?.description
                        let thumbnailUrl = searchResult?.thumbnailUrl
                        customNavigationClosure(title, url, snippet, thumbnailUrl)
                        print("🟢 [\(navTimestamp)] [FRAME:\(frameId)] IMMEDIATESTYLED: Custom navigation closure completed")
                    } else {
                        // Default navigation (for normal search tab)
                        print("🔴 [\(navTimestamp)] [FRAME:\(frameId)] IMMEDIATESTYLED: ❌❌❌ Using DEFAULT navigation (search tab context) ❌❌❌")
                        guard let appState = appState else { return }
                        if let searchResult = searchResult {
                            appState.navigateToArticle(
                                title: title,
                                url: url,
                                snippet: searchResult.description,
                                thumbnailUrl: searchResult.thumbnailUrl
                            )
                        } else {
                            appState.navigateToArticle(title: title, url: url)
                        }
                        print("🔴 [\(navTimestamp)] [FRAME:\(frameId)] IMMEDIATESTYLED: Default navigation completed")
                    }
                }
                viewModel = vm
            }
        }
        .onChange(of: searchText) { _, newValue in
            viewModel?.currentQuery = newValue
        }
    }
    
    private var searchInputSection: some View {
        VStack(spacing: 0) {
            // Search bar container
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(theme.placeholderColor))
                    
                    ImmediateStyledTextField(
                        text: $searchText,
                        placeholder: "Search OSRS Wiki",
                        onSubmit: performSearch,
                        theme: theme
                    )
                    
                    if !searchText.isEmpty {
                        Button(action: clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(theme.secondaryTextColor))
                        }
                    }
                    
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 44)
                .background(Color(theme.surfaceVariant))
                .cornerRadius(22)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Color(theme.background))
            
            // Recent searches - only show when empty
            if searchText.isEmpty, let vm = viewModel, !vm.recentSearches.isEmpty {
                recentSearchesSection(viewModel: vm)
                    .background(Color(theme.background))
            }
        }
    }
    
    private func recentSearchesSection(viewModel: SearchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Searches")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(theme.secondaryTextColor))
                
                Spacer()
                
                Button("Clear") {
                    viewModel.clearRecentSearches()
                }
                .font(.subheadline)
                .foregroundStyle(Color(theme.primary))
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.recentSearches.prefix(5), id: \.self) { search in
                        Button(search) {
                            searchText = search
                            performSearch()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(theme.surfaceVariant))
                        .foregroundStyle(Color(theme.secondaryTextColor))
                        .cornerRadius(16)
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var emptySearchState: some View {
        Spacer()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(theme.background))
    }
    
    private func performSearch() {
        guard let viewModel = viewModel,
              !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        viewModel.addToRecentSearches(searchText)
        
        Task {
            await viewModel.performSearch(query: searchText, isNewSearch: true)
        }
    }
    
    private func clearSearch() {
        searchText = ""
        viewModel?.currentQuery = ""
        viewModel?.clearSearchResults()
    }
}

// Separate content view for search results
private struct SearchContentSection: View {
    @ObservedObject var viewModel: SearchViewModel
    @Binding var searchText: String
    let theme: any osrsThemeProtocol
    let appState: AppState
    
    var body: some View {
        Group {
            if searchText.isEmpty {
                // Empty state when no search text
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(theme.background))
            } else if viewModel.isSearching && viewModel.searchResults.isEmpty {
                ProgressView("Searching...")
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(theme.primary)))
                    .foregroundStyle(Color(theme.secondaryTextColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                EmptyStateView(
                    iconName: "magnifyingglass",
                    title: "No Results",
                    subtitle: "Try different search terms"
                )
            } else {
                searchResultsList
            }
        }
        .alert("Search Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private var searchResultsList: some View {
        List {
            ForEach(viewModel.searchResults) { result in
                SearchResultRowView(result: ThemedSearchResult(
                    title: result.displayTitle,
                    snippet: result.rawSnippet,
                    description: result.namespace,
                    url: result.url.absoluteString,
                    thumbnailUrl: result.thumbnailUrl,
                    pageId: nil
                )) {
                    // Dismiss keyboard before navigation
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    
                    viewModel.selectSearchResult(result)
                    viewModel.addToRecentSearches(searchText)
                }
                .listRowBackground(Color(theme.surface))
            }
            
            // Load more section
            if viewModel.hasMoreResults {
                HStack {
                    Spacer()
                    if viewModel.isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color(theme.primary))
                    } else {
                        Button("Load More Results") {
                            Task {
                                await viewModel.loadMoreResults()
                            }
                        }
                        .foregroundStyle(Color(theme.primary))
                    }
                    Spacer()
                }
                .padding()
                .listRowBackground(Color(theme.surface))
                .onAppear {
                    Task {
                        await viewModel.loadMoreResults()
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color(theme.background))
    }
}
