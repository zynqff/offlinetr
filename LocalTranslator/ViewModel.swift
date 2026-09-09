import Foundation
import SwiftUI

@MainActor
final class TranslatorViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var preview = ""
    @Published var sourceLanguage = "English"
    @Published var targetLanguage = "Russian"
    @Published var history: [TranslationItem] = []
    @Published var modelState: ModelState = .unloaded
    @Published var isModelDownloading = false
    @Published var downloadProgress = 0.0
    @Published var errorMessage: String?
    @Published var config: RemoteAppConfig?

    let configService = ConfigService()
    let modelStore = ModelStore()
    let translator: LlamaTranslatorService
    let downloader = ModelDownloadService()

    private var idleTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var modelURL: URL?
    @AppStorage("idleTimeout") private var idleTimeout = 180

    init(translator: LlamaTranslatorService = LlamaTranslatorService()) {
        self.translator = translator
        Task { await refreshConfig() }
    }

    func refreshConfig() async {
        do {
            let c = try await configService.load()
            config = c
            modelURL = await modelStore.localURL(fileName: c.model.fileName)
        } catch {
            errorMessage = error.localizedDescription
        }
        await syncState()
    }

    func ensureModel() async throws {
        guard let config else { throw ConfigError.invalidConfig }
        let local = await modelStore.localURL(fileName: config.model.fileName)
        if !(await modelStore.exists(fileName: config.model.fileName)) {
            isModelDownloading = true
            do {
                let downloaded = try await downloader.download(url: config.model.url, fileName: config.model.fileName)
                let committed = try await modelStore.commit(downloadedFile: downloaded, fileName: config.model.fileName)
                try await modelStore.verify(url: committed, expectedSize: config.model.sizeBytes, expectedSHA256: config.model.sha256)
            } catch {
                isModelDownloading = false
                throw error
            }
            isModelDownloading = false
        }
        modelURL = local
    }

    func beginTyping() {
        guard !sourceText.isEmpty else { return }
        Task {
            do {
                if await translator.currentState() == .unloaded {
                    try await ensureModel()
                    if let modelURL { try await translator.loadModel(path: modelURL) }
                }
                await syncState()
            } catch { errorMessage = error.localizedDescription }
        }
        schedulePreview()
    }

    func schedulePreview() {
        previewTask?.cancel()
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { preview = ""; return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            do {
                if await self.translator.currentState() == .unloaded {
                    try await self.ensureModel()
                    if let modelURL = self.modelURL { try await self.translator.loadModel(path: modelURL) }
                }
                let result = try await self.translator.translate(text: self.sourceText, sourceLang: self.sourceLanguage, targetLang: self.targetLanguage)
                await MainActor.run { self.preview = result }
            } catch { }
        }
    }

    func finalize() {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !translated.isEmpty else { return }
        let item = TranslationItem(source: source, translated: translated, sourceLang: sourceLanguage, targetLang: targetLanguage, date: .now)
        history.append(item)
        HistoryStore.shared.add(item)
        sourceText = ""
        preview = ""
        scheduleIdleUnload()
    }

    func swapLanguages() {
        let old = sourceLanguage; sourceLanguage = targetLanguage; targetLanguage = old
        schedulePreview()
    }

    func clearScreen() { history.removeAll() }

    func deleteModel() async {
        guard let config else { return }
        try? await modelStore.remove(fileName: config.model.fileName)
        await translator.unloadModel()
        await syncState()
    }

    func appDidEnterBackground() {
        idleTask?.cancel()
        Task { await translator.unloadModel(); await syncState() }
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            let seconds = await MainActor.run { self?.idleTimeout ?? 180 }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            await self.translator.unloadModel()
            await self.syncState()
        }
    }

    func syncState() async { modelState = await translator.currentState() }
}
