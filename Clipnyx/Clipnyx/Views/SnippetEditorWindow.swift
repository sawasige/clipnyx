import SwiftUI

struct SnippetEditorView: View {
    var clipboardManager: ClipboardManager
    let item: ClipboardItem?
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedCategoryId: UUID?
    @State private var text: String = ""
    @State private var newCategoryName: String = ""
    @State private var showNewCategory = false

    private var isNewSnippet: Bool { item == nil }
    private var isTextEditable: Bool {
        guard let item else { return true }
        return item.category == .plainText
    }

    private let labelWidth: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Snippet Name
            HStack(alignment: .top) {
                Text("Snippet Name")
                    .frame(width: labelWidth, alignment: .trailing)
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Category
            if showNewCategory {
                HStack(alignment: .top) {
                    Text("Category")
                        .frame(width: labelWidth, alignment: .trailing)
                    TextField("New Category", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newCategoryName.isEmpty else { return }
                        let category = clipboardManager.addSnippetCategory(name: newCategoryName)
                        selectedCategoryId = category.id
                        newCategoryName = ""
                        showNewCategory = false
                    }
                    .disabled(newCategoryName.isEmpty)
                    Button("Cancel") {
                        showNewCategory = false
                        newCategoryName = ""
                    }
                }
            } else {
                HStack(alignment: .top) {
                    Text("Category")
                        .frame(width: labelWidth, alignment: .trailing)
                    Picker("", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(clipboardManager.snippetCategories.sorted(by: { $0.order < $1.order })) { cat in
                            Text(cat.name).tag(UUID?.some(cat.id))
                        }
                    }
                    .labelsHidden()
                    Button {
                        showNewCategory = true
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
                    Button("Unsave", role: .destructive) {
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
                Button(isNewSnippet ? "Create" : "Save") {
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
                name = item.snippetName ?? ""
                selectedCategoryId = item.snippetCategoryId
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
            clipboardManager.updateSnippet(item, name: name, categoryId: selectedCategoryId)
            if !text.isEmpty {
                clipboardManager.updateSnippetContent(item, text: text)
            }
        } else {
            clipboardManager.createSnippet(
                text: text,
                name: name,
                categoryId: selectedCategoryId
            )
        }
    }
}
