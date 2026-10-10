import AppKit
import LiteKeyCore
import LiteKeyEngine
import SwiftUI
import UniformTypeIdentifiers

/// Macro settings window: abbreviation and expansion fields, Add (Edit when the abbreviation exists) /
/// Delete buttons, the table, import/export to file, and the auto-capitalize option.
struct MacroView: View {
    @ObservedObject var macros: MacroModel
    @ObservedObject var prefs: PreferencesModel
    @State private var text = ""
    @State private var content = ""
    @State private var selection: Macro.ID?
    @State private var message: String?
    @State private var pendingFile: String?

    private static let textWidth: CGFloat = 140

    init(macros: MacroModel, prefs: PreferencesModel) {
        _macros = ObservedObject(wrappedValue: macros)
        _prefs = ObservedObject(wrappedValue: prefs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Từ gõ tắt")
                    TextField("", text: $text).frame(width: Self.textWidth)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nội dung đầy đủ")
                    TextField("", text: $content)
                }
                Button(macros.table.has(text) ? "Sửa" : "Thêm", action: add)
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
                Button("Xoá", action: delete)
                    .glassButton()
            }

            Table(macros.table.macros, selection: $selection) {
                // Narrower than the field above by the table's row insets, so the column divider falls in the
                // gap between the two fields
                TableColumn("Từ gõ tắt", value: \.text).width(Self.textWidth - 20)
                TableColumn("Nội dung đầy đủ", value: \.content)
            }
            .frame(minHeight: 260)
            .onChange(of: selection) { id in
                guard let id, let macro = macros.table.macros.first(where: { $0.id == id }) else { return }
                text = macro.text
                content = macro.content
            }

            HStack {
                Button("Nạp từ file...", action: loadFile)
                    .glassButton()
                Button("Xuất ra file...", action: exportFile)
                    .glassButton()
                Spacer()
                SwitchRow("Tự động viết hoa theo phím tắt", isOn: $prefs.preferences.autoCapsMacro, fill: false)
            }
        }
        .padding(16)
        .frame(width: 560)
        .alert("Gõ tắt", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .alert("Dữ liệu gõ tắt", isPresented: Binding(get: { pendingFile != nil }, set: { if !$0 { pendingFile = nil } })) {
            Button("Có") { applyFile(append: true) }
            Button("Không") { applyFile(append: false) }
        } message: {
            Text("Bạn có muốn giữ lại các dữ liệu hiện tại không?")
        }
    }

    private func add() {
        guard !text.isEmpty, !content.isEmpty else {
            message = "Bạn hãy nhập từ cần gõ tắt!"
            return
        }
        macros.table.add(text, content: content)
        text = ""
        content = ""
        selection = nil
    }

    private func delete() {
        guard !text.isEmpty else {
            message = "Bạn hãy chọn từ cần xoá!"
            return
        }
        if macros.table.delete(text) {
            text = ""
            content = ""
            selection = nil
        }
    }

    private func loadFile() {
        let panel = NSOpenPanel()
        panel.message = "Chọn file dữ liệu gõ tắt"
        panel.allowedContentTypes = [.plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // UniKey files may not be valid UTF-8, so decode leniently
        guard let data = try? Data(contentsOf: url) else { return }
        pendingFile = String(decoding: data, as: UTF8.self)
    }

    private func applyFile(append: Bool) {
        guard let file = pendingFile else { return }
        var table = macros.table
        table.load(fileText: file, append: append)
        macros.table = table
        pendingFile = nil
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.message = "Chọn nơi lưu dữ liệu gõ tắt"
        panel.title = "Chọn nơi lưu dữ liệu gõ tắt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "LiteKeyMacro.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? macros.table.fileText.write(to: url, atomically: true, encoding: .utf8)
    }
}
