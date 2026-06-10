import SwiftUI

struct FavoriteRegistrationView: View {
    var clipboardManager: ClipboardManager
    let item: ClipboardItem
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedFolderId: UUID?
    @State private var newFolderName: String = ""
    @State private var showNewFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Register as Favorite")
                .font(.headline)

            TextField("Favorite Name", text: $name)
                .textFieldStyle(.roundedBorder)

            if showNewFolder {
                HStack {
                    TextField("New Folder", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newFolderName.isEmpty else { return }
                        let folder = clipboardManager.addFavoriteFolder(name: newFolderName)
                        selectedFolderId = folder.id
                        newFolderName = ""
                        showNewFolder = false
                    }
                    .disabled(newFolderName.isEmpty)
                    Button("Cancel") {
                        showNewFolder = false
                        newFolderName = ""
                    }
                }
            } else {
                HStack {
                    Picker("Folder", selection: $selectedFolderId) {
                        Text("None").tag(UUID?.none)
                        ForEach(clipboardManager.favoriteFolders.sorted(by: { $0.order < $1.order })) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                    Button {
                        showNewFolder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Register") {
                    let folderId: UUID
                    if let selected = selectedFolderId {
                        folderId = selected
                    } else {
                        let folder = clipboardManager.addFavoriteFolder(name: String(localized: "General"))
                        folderId = folder.id
                    }
                    clipboardManager.registerAsFavorite(item, name: name, folderId: folderId)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            name = String(item.previewText.prefix(while: { $0 != "\n" }).prefix(50))
            selectedFolderId = clipboardManager.favoriteFolders.first?.id
        }
    }
}
