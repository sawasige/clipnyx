import SwiftUI

struct FavoriteEditorView: View {
    var clipboardManager: ClipboardManager
    let item: ClipboardItem?
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedFolderId: UUID?
    @State private var text: String = ""
    @State private var newFolderName: String = ""
    @State private var showNewFolder = false

    private var isNewFavorite: Bool { item == nil }
    private var isTextEditable: Bool {
        guard let item else { return true }
        return item.category == .plainText
    }

    private let labelWidth: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Favorite Name
            HStack(alignment: .top) {
                Text("Favorite Name")
                    .frame(width: labelWidth, alignment: .trailing)
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Folder
            if showNewFolder {
                HStack(alignment: .top) {
                    Text("Folder")
                        .frame(width: labelWidth, alignment: .trailing)
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
                HStack(alignment: .top) {
                    Text("Folder")
                        .frame(width: labelWidth, alignment: .trailing)
                    Picker("", selection: $selectedFolderId) {
                        Text("None").tag(UUID?.none)
                        ForEach(clipboardManager.favoriteFolders.sorted(by: { $0.order < $1.order })) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                    .labelsHidden()
                    Button {
                        showNewFolder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }

            Divider()

            // Content / Preview
            if isTextEditable {
                HStack(alignment: .top) {
                    Text("Content")
                        .frame(width: labelWidth, alignment: .trailing)
                    TextEditor(text: $text)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                }
            } else if let item {
                HStack(alignment: .top) {
                    Text("Preview")
                        .frame(width: labelWidth, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        if let thumbnailData = item.thumbnailData,
                           let nsImage = NSImage(data: thumbnailData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(item.previewText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(10)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                }
            }

            // Buttons
            HStack {
                if item?.isSaved == true {
                    Button("Unfavorite", role: .destructive) {
                        if let item {
                            clipboardManager.toggleSave(item)
                        }
                        onDismiss()
                    }
                }
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isNewFavorite ? "Create" : "Save") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    save()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: !isTextEditable)
        .onAppear {
            if let item {
                name = item.favoriteName ?? ""
                selectedFolderId = item.favoriteFolderId
                if let reps = clipboardManager.store.loadRepresentations(for: item.id),
                   let stringRep = reps.first(where: { $0.pasteboardType == .string }),
                   let str = String(data: stringRep.data, encoding: .utf8) {
                    text = str
                } else {
                    text = item.previewText
                }
            }
        }
    }

    private func save() {
        if let item {
            if !item.isSaved {
                clipboardManager.toggleSave(item)
            }
            clipboardManager.updateFavoriteName(item, name: name)
            clipboardManager.updateFavoriteFolder(item, folderId: selectedFolderId)
            if !text.isEmpty {
                clipboardManager.updateFavoriteContent(item, text: text)
            }
        } else {
            clipboardManager.createFavorite(
                text: text,
                name: name,
                folderId: selectedFolderId
            )
        }
    }
}
