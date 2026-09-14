import Foundation
import llama
import os

// Через os.Logger, а не print()/NSLog() — так эти сообщения гарантированно попадают
// в единый системный лог (видно в Console.app / idevicesyslog), в отличие от обычного
// print() или fprintf(stderr, ...) внутри llama.cpp, которые в собранном не под Xcode
// приложении в системный лог не долетают вообще.
private let llamaLogger = Logger(subsystem: "com.example.LocalTranslator", category: "llama")

// llama.cpp/ggml по умолчанию пишет свои внутренние сообщения (в т.ч. настоящую причину
// сбоя загрузки — неподдерживаемая архитектура/квантование/битая gguf) через fprintf(stderr,...),
// которые в собранном приложении в системный лог НЕ попадают. llama_log_set перехватывает
// эти сообщения и переправляет в os.Logger, чтобы их было видно в Console.app / idevicesyslog.
private func llamaLogCallback(level: ggml_log_level, text: UnsafePointer<CChar>?, userData: UnsafeMutableRawPointer?) {
    guard let text else { return }
    let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }
    switch level {
    case GGML_LOG_LEVEL_ERROR:
        llamaLogger.error("llama.cpp: \(message, privacy: .public)")
    case GGML_LOG_LEVEL_WARN:
        llamaLogger.warning("llama.cpp: \(message, privacy: .public)")
    default:
        llamaLogger.notice("llama.cpp: \(message, privacy: .public)")
    }
}

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
    /// onToken вызывается по мере генерации каждого нового фрагмента текста (потоковый вывод).
    /// Возвращает финальный, уже полностью собранный и обрезанный от пробелов результат.
    func translate(text: String, sourceLang: String, targetLang: String, onToken: @escaping @Sendable (String) -> Void) async throws -> String
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

    func translate(text: String, sourceLang: String, targetLang: String, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let context else { throw TranslatorError.modelUnavailable }
        state = .translating
        defer { if self.context != nil { self.state = .loaded } }

        let prompt = "Translate the following segment into \(targetLang), without additional explanation: \(text)"
        do {
            // maxTokens здесь — это "запрошенный потолок", а не гарантия: generate() сам
            // урежет его под реально доступный остаток контекста (n_ctx - размер промпта),
            // так что жёстко попадать в TranslatorError.inputTooLong он будет, только если
            // сам промпт уже не помещается в контекст целиком.
            let result = try await context.generate(prompt: prompt, maxTokens: 2048, onToken: onToken)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranslatorError {
            throw error
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
        // Диагностика HY-MT2: сначала используем полностью детерминированный
        // greedy sampler, чтобы исключить влияние top-k/top-p/temperature,
        // penalties и случайного seed на качество первых токенов.
        self.sampling = llama_sampler_init_greedy()
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    static func create(path: String) throws -> LlamaContext {
        llama_log_set(llamaLogCallback, nil)
        llama_backend_init()
        var modelParams = llama_model_default_params()
        // ВРЕМЕННО для диагностики: принудительно 0 GPU-слоёв даже на реальном
        // устройстве (было Int32.max), чтобы проверить гипотезу "Metal-офлоад
        // новой архитектуры hy_v3 даёт мусор на выходе, а чистый CPU — нет".
        // После проверки строку ниже нужно вернуть на исходную (см. комментарий).
        modelParams.n_gpu_layers = 0
        // #if targetEnvironment(simulator)
        // modelParams.n_gpu_layers = 0
        // #else
        // modelParams.n_gpu_layers = Int32.max   // <- вернуть после диагностики
        // #endif
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

    func generate(prompt: String, maxTokens: Int32, onToken: @escaping @Sendable (String) -> Void) throws -> String {
        // Важно: чистим KV-кэш перед КАЖДЫМ новым переводом. Раньше context/кэш
        // переиспользовался между вызовами, а позиции токенов снова нумеровались с
        // нуля — старые записи кэша от предыдущего перевода оставались и мешались
        // с новыми, из-за чего 2-й и последующие переводы съезжали в мусор.
        llama_memory_clear(llama_get_memory(context), true)
        nCur = 0

        // HY-MT2 — chat-модель. Используем именно Hunyuan chat template и
        // НЕ делаем fallback на raw prompt: raw prompt имеет другой формат и
        // может приводить к полностью неправильной генерации.
        guard let formattedPrompt = applyChatTemplate(userContent: prompt) else {
            llamaLogger.error("generate: не удалось применить chat template hunyuan-dense")
            throw TranslatorError.inferenceFailed
        }
        // Шаблон уже содержит <｜hy_begin▁of▁sentence｜> (BOS), поэтому
        // автоматически добавлять BOS через llama_tokenize нельзя — это даст дубль.
        let shouldAddBOS = false
        llamaLogger.notice("generate: chat_template hunyuan-dense применён, prompt=\(formattedPrompt, privacy: .public)")
        // parse_special: true — обязательно, чтобы специальные токены HY-MT2
        // оставались управляющими токенами, а не разбивались на обычные подтокены.
        let tokens = tokenize(formattedPrompt, addBOS: shouldAddBOS, parseSpecial: true)

        // Динамический лимит: сколько токенов реально осталось в контексте после промпта.
        // Раньше здесь была жёсткая проверка "tokens.count + maxTokens <= n_ctx", которая
        // при фиксированном большом maxTokens (например 4096 при n_ctx=2048) падала ВСЕГДА,
        // независимо от длины входного текста. Теперь maxTokens — это лишь верхняя граница,
        // фактически используемая величина не может превысить свободное место в контексте.
        let available = Int(llama_n_ctx(context)) - tokens.count
        guard available > 0 else { throw TranslatorError.inputTooLong }
        let effectiveMaxTokens = min(Int(maxTokens), available)

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
        for _ in 0..<effectiveMaxTokens {
            let token = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocab, token) { break }
            let chars = tokenToPiece(token)
            invalidUTF8.append(contentsOf: chars)
            if let str = String(validatingUTF8: invalidUTF8 + [0]) {
                output += str
                invalidUTF8.removeAll(keepingCapacity: true)
                // Отдаём наружу только что декодированный кусок текста — это и даёт
                // потоковый вывод в UI, а не ожидание полного результата в конце.
                onToken(str)
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

    private func tokenize(_ text: String, addBOS: Bool, parseSpecial: Bool = false) -> [llama_token] {
        let count = text.utf8.count
        let capacity = count + (addBOS ? 1 : 0) + 1
        let ptr = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { ptr.deallocate() }
        let n = llama_tokenize(vocab, text, Int32(count), ptr, Int32(capacity), addBOS, parseSpecial)
        return (0..<max(0, Int(n))).map { ptr[$0] }
    }

    /// Формирует точный chat prompt из metadata GGUF HY-MT2.
    /// Не используем llama_chat_apply_template(): llama.cpp в этой версии
    /// поддерживает только заранее встроенный список шаблонов и не исполняет
    /// произвольный Jinja template из GGUF. Для HY-MT2 безопаснее повторить
    /// его template буквально.
    private func applyChatTemplate(userContent: String) -> String? {
        // Из metadata GGUF:
        // <｜hy_begin▁of▁sentence｜><｜hy_User｜>{{ content }}<｜hy_Assistant｜>
        return "<｜hy_begin▁of▁sentence｜><｜hy_User｜>\(userContent)<｜hy_Assistant｜>"
    }

    private func tokenToPiece(_ token: llama_token) -> [CChar] {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n <= 0 { return [] }
        return Array(buffer.prefix(Int(n)))
    }
}
