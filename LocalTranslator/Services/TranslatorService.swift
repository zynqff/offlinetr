import Foundation
import llama
import os

// Через os.Logger, а не print()/NSLog() — так эти сообщения гарантированно попадают
// в единый системный лог (видно в Console.app / idevicesyslog), в отличие от обычного
// print() или fprintf(stderr, ...) внутри llama.cpp, которые в собранном не под Xcode
// приложении в системный лог не долетают вообще.
private let llamaLogger = Logger(subsystem: "com.example.LocalTranslator", category: "llama")

enum ModelState: Equatable, Sendable {
    case unloaded, loading, loaded, translating, unloading
}

enum TranslatorError: LocalizedError {
    case modelUnavailable
    case contextCreationFailed
    case inferenceFailed
    case inputTooLong

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "Модель недоступна."
        case .contextCreationFailed: return "Не удалось загрузить модель в память."
        case .inferenceFailed: return "Не удалось выполнить перевод."
        case .inputTooLong: return "Текст слишком длинный для текущего контекста."
        }
    }
}

protocol TranslatorService: Sendable {
    func loadModel(path: URL) async throws
    func translate(text: String, sourceLang: String, targetLang: String) async throws -> String
    func unloadModel() async
    func currentState() async -> ModelState
}

actor LlamaTranslatorService: TranslatorService {
    private var context: LlamaContext?
    private var state: ModelState = .unloaded

    func currentState() async -> ModelState { state }

    func loadModel(path: URL) async throws {
        guard context == nil else { return }
        state = .loading
        llamaLogger.notice("loadModel: старт, путь = \(path.path, privacy: .public)")
        let exists = FileManager.default.fileExists(atPath: path.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int64) ?? nil
        llamaLogger.notice("loadModel: файл существует = \(exists), размер на диске = \(size ?? -1, privacy: .public) байт")
        do {
            context = try await LlamaContext.create(path: path.path)
            state = .loaded
            llamaLogger.notice("loadModel: модель и контекст успешно созданы")
        } catch {
            context = nil
            state = .unloaded
            llamaLogger.error("loadModel: ошибка создания контекста: \(String(describing: error), privacy: .public)")
            throw TranslatorError.contextCreationFailed
        }
    }

    func translate(text: String, sourceLang: String, targetLang: String) async throws -> String {
        guard let context else { throw TranslatorError.modelUnavailable }
        state = .translating
        defer { if self.context != nil { self.state = .loaded } }

        let prompt = "Translate the following segment into \(targetLang), without additional explanation: \(text)"
        do {
            let result = try await context.generate(prompt: prompt, maxTokens: 4096)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranslatorError.inferenceFailed
        }
    }

    func unloadModel() async {
        state = .unloading
        context = nil
        state = .unloaded
    }
}

actor LlamaContext {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var nCur: Int32 = 0
    private var invalidUTF8: [CChar] = []

    private init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.batch = llama_batch_init(512, 0, 1)
        let params = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(params)
        llama_sampler_chain_add(sampling, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(sampling, llama_sampler_init_top_p(0.6, 1))
        llama_sampler_chain_add(sampling, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(
            sampling, 
            llama_sampler_init_penalties(
                Int32(64),      // n_vocab (или размер вашего словаря/пенальти)
                Int32(64),      // penalty_last_n
                Float(1.05),    // penalty_repeat
                Float(0.0),     // penalty_freq
                Float(0.0)      // penalty_present
            )
        )
        llama_sampler_chain_add(sampling, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    static func create(path: String) throws -> LlamaContext {
        llama_backend_init()
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = Int32.max
        #endif
        llamaLogger.notice("LlamaContext.create: вызываю llama_model_load_from_file (n_gpu_layers=\(modelParams.n_gpu_layers, privacy: .public))")

        guard let model = llama_model_load_from_file(path, modelParams) else {
            llamaLogger.error("LlamaContext.create: llama_model_load_from_file вернул nil — файл не распознан как валидный gguf/архитектура/квантование не поддерживаются текущей сборкой llama.xcframework")
            llama_backend_free()
            throw TranslatorError.contextCreationFailed
        }
        llamaLogger.notice("LlamaContext.create: модель загружена, создаю контекст")

        let threads = max(1, min(6, ProcessInfo.processInfo.activeProcessorCount))
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_threads = Int32(threads)
        contextParams.n_threads_batch = Int32(threads)
        guard let context = llama_init_from_model(model, contextParams) else {
            llamaLogger.error("LlamaContext.create: llama_init_from_model вернул nil (n_ctx=2048, threads=\(threads, privacy: .public)) — вероятно не хватает памяти под контекст, либо параметры контекста несовместимы с моделью")
            llama_model_free(model)
            llama_backend_free()
            throw TranslatorError.contextCreationFailed
        }
        llamaLogger.notice("LlamaContext.create: контекст создан успешно")
        return LlamaContext(model: model, context: context)
    }

    func generate(prompt: String, maxTokens: Int32) throws -> String {
        let tokens = tokenize(prompt, addBOS: true)
        guard tokens.count + Int(maxTokens) <= Int(llama_n_ctx(context)) else {
            throw TranslatorError.inputTooLong
        }

        batch.n_tokens = 0
        for (i, token) in tokens.enumerated() {
            batch.token[Int(batch.n_tokens)] = token
            batch.pos[Int(batch.n_tokens)] = Int32(i)
            batch.n_seq_id[Int(batch.n_tokens)] = 1
            batch.seq_id[Int(batch.n_tokens)]![0] = 0
            batch.logits[Int(batch.n_tokens)] = 0
            batch.n_tokens += 1
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1
        guard llama_decode(context, batch) == 0 else { throw TranslatorError.inferenceFailed }
        nCur = batch.n_tokens
        invalidUTF8.removeAll(keepingCapacity: true)

        var output = ""
        for _ in 0..<maxTokens {
            let token = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocab, token) { break }
            let chars = tokenToPiece(token)
            invalidUTF8.append(contentsOf: chars)
            if let str = String(validatingUTF8: invalidUTF8 + [0]) {
                output += str
                invalidUTF8.removeAll(keepingCapacity: true)
            }

            batch.n_tokens = 0
            batch.token[0] = token
            batch.pos[0] = nCur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            batch.n_tokens = 1
            guard llama_decode(context, batch) == 0 else { throw TranslatorError.inferenceFailed }
            nCur += 1
        }
        return output
    }

    private func tokenize(_ text: String, addBOS: Bool) -> [llama_token] {
        let count = text.utf8.count
        let capacity = count + (addBOS ? 1 : 0) + 1
        let ptr = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { ptr.deallocate() }
        let n = llama_tokenize(vocab, text, Int32(count), ptr, Int32(capacity), addBOS, false)
        return (0..<max(0, Int(n))).map { ptr[$0] }
    }

    private func tokenToPiece(_ token: llama_token) -> [CChar] {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n <= 0 { return [] }
        return Array(buffer.prefix(Int(n)))
    }
}
