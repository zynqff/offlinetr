import SwiftUI

struct TranslationView: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.history) { item in
                                TranslationCard(item: item)
                            }
                            if vm.isModelDownloading {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Загрузка модели…").font(.headline)
                                    ProgressView(value: vm.downloader.progress)
                                    Text("\(Int(vm.downloader.progress * 100))% · \(formatBytes(vm.downloader.downloadedBytes)) / \(formatBytes(vm.downloader.totalBytes))").font(.caption).foregroundStyle(.secondary)
                                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16)).id("bottom")
                            }
                        }.padding()
                    }
                    .onChange(of: vm.history.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                }

                VStack(spacing: 10) {
                    HStack {
                        Picker("Источник", selection: $vm.sourceLanguage) { ForEach(supportedLanguages, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
                        Button { vm.swapLanguages() } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.plain)
                        Picker("Перевод", selection: $vm.targetLanguage) { ForEach(supportedLanguages, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
                    }
                    TextField("Введите текст…", text: $vm.sourceText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onChange(of: vm.sourceText) { vm.beginTyping() }
                        .onSubmit { vm.finalize() }
                    HStack {
                        if !vm.preview.isEmpty { Text(vm.preview).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.secondary) }
                        Button { UIPasteboard.general.string = vm.preview } label: { Image(systemName: "doc.on.doc") }.disabled(vm.preview.isEmpty)
                        Button("Далее") { vm.finalize() }.buttonStyle(.borderedProminent)
                    }
                }.padding()
            }
            .navigationTitle("Переводчик")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Очистить") { vm.clearScreen() } }
                ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
                ToolbarItem(placement: .principal) { HStack(spacing: 5) { Circle().fill(vm.modelState == .loaded ? .green : .secondary).frame(width: 8, height: 8); Text(stateText) } }
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(vm) }
        }
        .onChange(of: scenePhase) { phase in if phase == .background { vm.appDidEnterBackground() } }
        .alert("Ошибка", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) { Button("OK") {} } message: { Text(vm.errorMessage ?? "") }
    }

    private var stateText: String { switch vm.modelState { case .unloaded: return "модель выгружена"; case .loading: return "загрузка…"; case .loaded: return "готово"; case .translating: return "перевод…"; case .unloading: return "выгрузка…" } }
    private func formatBytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}

private struct TranslationCard: View {
    let item: TranslationItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.source).font(.body)
            Divider()
            HStack { Text(item.translated).font(.body); Spacer(); Button { UIPasteboard.general.string = item.translated } label: { Image(systemName: "doc.on.doc") } }
            Text("\(item.sourceLang) → \(item.targetLang)").font(.caption).foregroundStyle(.secondary)
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
