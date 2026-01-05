import SwiftUI

// MARK: - Downloaded Models View with Search, Filter & Sort

public struct DownloadedModelsView: View {
    @StateObject private var viewModel = DownloadedModelsViewModel()
    @Environment(\.editMode) private var editMode
    @State private var searchText = ""
    @State private var showSortOptions = false
    @State private var showFilterOptions = false
    
    public init() {}
    
    var filteredModels: [DownloadedModel] {
        var models = viewModel.models
        
        // Apply search filter
        if !searchText.isEmpty {
            models = models.filter { model in
                model.metadata?.modelName.localizedCaseInsensitiveContains(searchText) ?? false ||
                model.modelId.localizedCaseInsensitiveContains(searchText) ||
                model.metadata?.description.localizedCaseInsensitiveContains(searchText) ?? false ||
                model.metadata?.category.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Apply category filter
        if let selectedCategory = viewModel.selectedCategory, selectedCategory != "All" {
            models = models.filter { model in
                model.metadata?.category == selectedCategory
            }
        }
        
        // Apply type filter
        switch viewModel.selectedTypeFilter {
        case .compiled:
            models = models.filter { $0.isCompiled }
        case .regular:
            models = models.filter { !$0.isCompiled }
        case .all:
            break
        }
        
        // Apply sorting
        switch viewModel.sortOption {
        case .nameAscending:
            models.sort { ($0.metadata?.modelName ?? $0.modelId) < ($1.metadata?.modelName ?? $1.modelId) }
        case .nameDescending:
            models.sort { ($0.metadata?.modelName ?? $0.modelId) > ($1.metadata?.modelName ?? $1.modelId) }
        case .dateNewest:
            models.sort { ($0.metadata?.downloadDate ?? Date.distantPast) > ($1.metadata?.downloadDate ?? Date.distantPast) }
        case .dateOldest:
            models.sort { ($0.metadata?.downloadDate ?? Date.distantPast) < ($1.metadata?.downloadDate ?? Date.distantPast) }
        case .sizeLargest:
            models.sort { $0.fileSize > $1.fileSize }
        case .sizeSmallest:
            models.sort { $0.fileSize < $1.fileSize }
        }
        
        return models
    }
    
    public var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading models...")
            } else if viewModel.models.isEmpty {
                emptyStateView
            } else {
                modelListView
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search models")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if !viewModel.models.isEmpty {
                        Button(action: {
                            withAnimation {
                                if editMode?.wrappedValue.isEditing == true {
                                    editMode?.wrappedValue = .inactive
                                } else {
                                    editMode?.wrappedValue = .active
                                }
                            }
                        }) {
                            Label(
                                editMode?.wrappedValue.isEditing == true ? "Done" : "Select",
                                systemImage: editMode?.wrappedValue.isEditing == true ? "checkmark.circle" : "checkmark.circle"
                            )
                        }
                        
                        Divider()
                    }
                    
                    Button(action: { showSortOptions = true }) {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    
                    Button(action: { showFilterOptions = true }) {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    
                    Divider()
                    
                    Button(action: { viewModel.loadModels() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                if editMode?.wrappedValue.isEditing == true {
                    Button("Delete All") {
                        viewModel.showDeleteAllAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            viewModel.loadModels()
        }
        .refreshable {
            viewModel.loadModels()
        }
        .sheet(isPresented: $showSortOptions) {
            SortOptionsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showFilterOptions) {
            FilterOptionsSheet(viewModel: viewModel)
        }
        .alert("Delete All Models", isPresented: $viewModel.showDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllModels()
                withAnimation {
                    editMode?.wrappedValue = .inactive
                }
            }
        } message: {
            Text("Are you sure you want to delete all \(viewModel.models.count) models? This action cannot be undone.")
        }
        .alert("Delete Model", isPresented: $viewModel.showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let model = viewModel.modelToDelete {
                    viewModel.deleteModel(model)
                }
            }
        } message: {
            if let model = viewModel.modelToDelete {
                Text("Are you sure you want to delete '\(model.metadata?.modelName ?? model.modelId)'?")
            }
        }
    }
    
    // MARK: - Model List View
    private var modelListView: some View {
        List {
            // Summary Section
            Section {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(filteredModels.count) of \(viewModel.models.count) Models")
                                .font(.headline)
                            Text(viewModel.totalSizeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "cube.box.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    // Active filters indicator
                    if viewModel.hasActiveFilters || !searchText.isEmpty {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Filters active")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                            Button("Clear") {
                                searchText = ""
                                viewModel.clearFilters()
                            }
                            .font(.caption)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Models Section
            if filteredModels.isEmpty && !viewModel.models.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No models match your search")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section {
                    ForEach(filteredModels) { model in
                        NavigationLink(destination: ModelDetailView(model: model, viewModel: viewModel)) {
                            ModelRowCompact(model: model)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.modelToDelete = model
                                viewModel.showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                viewModel.modelToDelete = model
                                viewModel.showDeleteAlert = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let modelsToDelete = indexSet.map { filteredModels[$0] }
                        for model in modelsToDelete {
                            viewModel.deleteModel(model)
                        }
                    }
                } header: {
                    HStack {
                        Text("Models")
                        Spacer()
                        Text(viewModel.sortOption.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.box")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Downloaded Models")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Download models to see them here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Compact Model Row
struct ModelRowCompact: View {
    let model: DownloadedModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.isCompiled ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: model.isCompiled ? "checkmark.seal.fill" : "cube.fill")
                    .foregroundColor(model.isCompiled ? .green : .blue)
                    .font(.title3)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(model.metadata?.modelName ?? model.modelId)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    if let category = model.metadata?.category {
                        Label(category, systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Label(model.fileSizeString, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model Detail View
struct ModelDetailView: View {
    let model: DownloadedModel
    @ObservedObject var viewModel: DownloadedModelsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            // Basic Info Section
            Section("Model Information") {
                DetailRow(label: "Name", value: model.metadata?.modelName ?? "Unknown")
                
#if DEBUG
                DetailRow(label: "Model ID", value: model.modelId)
#endif
                
                if let version = model.metadata?.version {
                    DetailRow(label: "Version", value: version)
                }
                
                if let category = model.metadata?.category {
                    DetailRow(label: "Category", value: category)
                }
            }
            
            // Description Section
            if let description = model.metadata?.description, !description.isEmpty {
                Section("Description") {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            
            // File Info Section
            Section("File Information") {
                DetailRow(label: "Size", value: model.fileSizeString)
#if DEBUG
                DetailRow(label: "Path", value: model.modelURL.path)
#endif
                
                if let date = model.metadata?.downloadDate {
                    DetailRow(label: "Downloaded", value: formatFullDate(date))
                }
            }
            
            // Actions Section
            Section {
                
                Button(role: .destructive, action: {
                    viewModel.modelToDelete = model
                    viewModel.showDeleteAlert = true
                    dismiss()
                }) {
                    Label("Delete Model", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Model Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row Component
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sort Options Sheet
struct SortOptionsSheet: View {
    @ObservedObject var viewModel: DownloadedModelsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Sort By") {
                    ForEach(ModelSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            viewModel.sortOption = option
                            dismiss()
                        }) {
                            HStack {
                                Label(option.displayName, systemImage: option.icon)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.sortOption == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sort Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Filter Options Sheet
struct FilterOptionsSheet: View {
    @ObservedObject var viewModel: DownloadedModelsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Type Filter
                Section("Model Type") {
                    ForEach(ModelTypeFilter.allCases, id: \.self) { type in
                        Button(action: {
                            viewModel.selectedTypeFilter = type
                        }) {
                            HStack {
                                Label(type.displayName, systemImage: type.icon)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedTypeFilter == type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                // Category Filter
                if !viewModel.availableCategories.isEmpty {
                    Section("Category") {
                        ForEach(viewModel.availableCategories, id: \.self) { category in
                            Button(action: {
                                viewModel.selectedCategory = category == "All" ? nil : category
                            }) {
                                HStack {
                                    Label(category, systemImage: "folder.fill")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if (category == "All" && viewModel.selectedCategory == nil) ||
                                        (viewModel.selectedCategory == category) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Clear filters
                Section {
                    Button(action: {
                        viewModel.clearFilters()
                        dismiss()
                    }) {
                        Label("Clear All Filters", systemImage: "xmark.circle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Filter Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Sort Option Enum
public enum ModelSortOption: CaseIterable {
    case dateNewest
    case dateOldest
    case nameAscending
    case nameDescending
    case sizeLargest
    case sizeSmallest
    
    public var displayName: String {
        switch self {
        case .dateNewest: return "Newest First"
        case .dateOldest: return "Oldest First"
        case .nameAscending: return "Name (A-Z)"
        case .nameDescending: return "Name (Z-A)"
        case .sizeLargest: return "Largest First"
        case .sizeSmallest: return "Smallest First"
        }
    }
    
    public var icon: String {
        switch self {
        case .dateNewest, .dateOldest: return "calendar"
        case .nameAscending, .nameDescending: return "textformat"
        case .sizeLargest, .sizeSmallest: return "internaldrive"
        }
    }
}

// MARK: - Type Filter Enum
public enum ModelTypeFilter: CaseIterable {
    case all
    case compiled
    case regular
    
    public var displayName: String {
        switch self {
        case .all: return "All Models"
        case .compiled: return "Compiled Only"
        case .regular: return "Regular Only"
        }
    }
    
    public var icon: String {
        switch self {
        case .all: return "cube.box"
        case .compiled: return "checkmark.seal.fill"
        case .regular: return "cube"
        }
    }
}

// MARK: - Enhanced View Model
public class DownloadedModelsViewModel: ObservableObject {
    @Published public var models: [DownloadedModel] = []
    @Published public var isLoading = false
    @Published public var showDeleteAlert = false
    @Published public var showDeleteAllAlert = false
    @Published public var modelToDelete: DownloadedModel?
    @Published public var sortOption: ModelSortOption = .dateNewest
    @Published public var selectedTypeFilter: ModelTypeFilter = .all
    @Published public var selectedCategory: String?
    
    private let client = EdgenAIClient()
    private let fileManager = FileManager.default
    
    public init() {}
    
    public var totalSizeString: String {
        let totalSize = models.reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    public var availableCategories: [String] {
        var categories = Set<String>()
        for model in models {
            if let category = model.metadata?.category, !category.isEmpty {
                categories.insert(category)
            }
        }
        var sorted = Array(categories).sorted()
        sorted.insert("All", at: 0)
        return sorted
    }
    
    public var hasActiveFilters: Bool {
        return selectedCategory != nil || selectedTypeFilter != .all
    }
    
    public func clearFilters() {
        selectedCategory = nil
        selectedTypeFilter = .all
        sortOption = .dateNewest
    }
    
    // MARK: - Load Models
    public func loadModels() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let documentsPath = self.fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            
            var downloadedModels: [DownloadedModel] = []
            
            do {
                let files = try self.fileManager.contentsOfDirectory(
                    at: documentsPath,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
                )
                
                // Find all metadata files
                let metadataFiles = files.filter { $0.lastPathComponent.hasSuffix("_metadata") }
                
                for metadataURL in metadataFiles {
                    // Extract model ID from metadata filename
                    let filename = metadataURL.lastPathComponent
                    let modelId = filename.replacingOccurrences(of: "_metadata", with: "")
                    
                    // Check if model file exists
                    let compiledURL = documentsPath.appendingPathComponent("\(modelId).mlmodelc")
                    let regularURL = documentsPath.appendingPathComponent(modelId)
                    
                    var modelURL: URL?
                    var isCompiled = false
                    
                    if self.fileManager.fileExists(atPath: compiledURL.path) {
                        modelURL = compiledURL
                        isCompiled = true
                    } else if self.fileManager.fileExists(atPath: regularURL.path) {
                        modelURL = regularURL
                        isCompiled = false
                    }
                    
                    guard let foundModelURL = modelURL else { continue }
                    
                    // Load metadata
                    var metadata: ModelMetadata?
                    do {
                        let data = try Data(contentsOf: metadataURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        metadata = try decoder.decode(ModelMetadata.self, from: data)
                    } catch {
                        EdgenLogger.error("Failed to parse metadata for \(modelId): \(error)")
                    }
                    
                    // Get file size
                    let fileSize = self.getFileSize(url: foundModelURL)
                    
                    let model = DownloadedModel(
                        modelId: modelId,
                        modelURL: foundModelURL,
                        metadataURL: metadataURL,
                        metadata: metadata,
                        fileSize: fileSize,
                        isCompiled: isCompiled
                    )
                    
                    downloadedModels.append(model)
                }
                
                // Sort by download date (newest first)
                downloadedModels.sort { model1, model2 in
                    guard let date1 = model1.metadata?.downloadDate,
                          let date2 = model2.metadata?.downloadDate else {
                        return false
                    }
                    return date1 > date2
                }
                
            } catch {
                EdgenLogger.error("Failed to load models: \(error)")
            }
            
            DispatchQueue.main.async {
                self.models = downloadedModels
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Get File Size
    private func getFileSize(url: URL) -> Int64 {
        do {
            // If it's a directory (compiled model), calculate total size
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return calculateDirectorySize(url: url)
            } else {
                // Single file
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                return attributes[.size] as? Int64 ?? 0
            }
        } catch {
            return 0
        }
    }
    
    // MARK: - Calculate Directory Size
    private func calculateDirectorySize(url: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let size = attributes[.size] as? Int64 {
                        totalSize += size
                    }
                } catch {
                    continue
                }
            }
        }
        
        return totalSize
    }
    
    // MARK: - Delete Model
    public func deleteModel(_ model: DownloadedModel) {
        // Delete model file
        try? fileManager.removeItem(at: model.modelURL)
        
        // Delete metadata file
        if let metadataURL = model.metadataURL {
            try? fileManager.removeItem(at: metadataURL)
        }
        
        // Delete any progress state file
        client.cancelDownload(modelId: model.modelId)
        
        // Reload models
        loadModels()
    }
    
    // MARK: - Delete Models at Index Set
    func deleteModels(at indexSet: IndexSet) {
        for index in indexSet {
            let model = models[index]
            deleteModel(model)
        }
    }
    
    // MARK: - Delete All Models
    public func deleteAllModels() {
        for model in models {
            deleteModel(model)
        }
    }
}
