import Foundation
import llama

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
        do {
            context = try await LlamaContext.create(path: path.path)
            state = .loaded
        } catch {
            context = nil
            state = .unloaded
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
        llama_sampler_chain_add(sampling, llama_sampler_init_penalties(Int32(64), Float(1.05), Float(0.0), Float(0.0)))
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

        guard let model = llama_model_load_from_file(path, modelParams) else {
            llama_backend_free()
            throw TranslatorError.contextCreationFailed
        }

        let threads = max(1, min(6, ProcessInfo.processInfo.activeProcessorCount))
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_threads = UInt32(threads)
        contextParams.n_threads_batch = UInt32(threads)
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            llama_backend_free()
            throw TranslatorError.contextCreationFailed
        }
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
