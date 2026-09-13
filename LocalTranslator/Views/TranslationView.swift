import SwiftUI

struct TranslationView: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var showClearedSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                statusBanner

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if vm.history.isEmpty {
                                emptyState
                            }
                            ForEach(vm.history) { item in
                                TranslationCard(item: item)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding()
                    }
<<<<<<< HEAD
                    .onChange(of: vm.history.count) { _ in 
                        proxy.scrollTo("bottom", anchor: .bottom) 
                    }
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
                        .onChange(of: vm.sourceText) { _ in 
                            vm.beginTyping() 
                        }
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
=======
                    // Прокрутка истории вверх скрывает клавиатуру; чтобы показать её
                    // снова — нужно нажать на поле ввода.
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: vm.history.count) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                composer
>>>>>>> 700a3b5 (feat(ios): add llama.framework to local translator app)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(vm) }
        }
        .onChange(of: scenePhase) { phase in if phase == .background { vm.appDidEnterBackground() } }
        .alert("Ошибка", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) { Button("OK") {} } message: { Text(vm.errorMessage ?? "") }
        .confirmationDialog(
            "Вы уверены, что хотите очистить историю переводов?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Очистить", role: .destructive) {
                vm.clearHistoryConfirmed()
                showClearedSuccess = true
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Готово", isPresented: $showClearedSuccess) {
            Button("ОК") {}
        } message: {
            Text("История переводов успешно очищена.")
        }
    }

    // MARK: - Верхняя панель (заменяет системный navigationBar)
    // По умолчанию справа только кнопка настроек. Как только пользователь
    // нажимает на поле ввода, кнопка настроек «сдвигается» влево, освобождая
    // место для галочки подтверждения (как и кнопка «Далее», она завершает перевод).

    private var header: some View {
        HStack {
            Button("Очистить") { showClearConfirm = true }
                .foregroundStyle(vm.history.isEmpty ? Color.secondary : Color.primary)
                .disabled(vm.history.isEmpty)

            Spacer()

            Text("Перевод").font(.headline)

            Spacer()

            HStack(spacing: 18) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }

                if focused {
                    Button { finalizeAndKeepEditing() } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(Color.accentColor)
                    .disabled(vm.preview.isEmpty)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: focused)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Баннер состояния модели (всегда виден, не требует скролла)

    @ViewBuilder
    private var statusBanner: some View {
        if vm.isModelDownloading {
            VStack(alignment: .leading, spacing: 6) {
                Text("Загрузка модели перевода…").font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    ProgressView(value: vm.downloader.progress)
                    Text("\(Int(vm.downloader.progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.12))
        } else if vm.config != nil && !vm.isModelInstalled {
            HStack {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Нужно скачать модель перевода").font(.subheadline.weight(.semibold))
                    if let size = vm.config?.model.sizeBytes {
                        Text("Размер ~\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), перевод работает офлайн").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Загрузить") {
                    Task {
                        do { try await vm.ensureModel() } catch { vm.errorMessage = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.thinMaterial)
        }
    }

    // MARK: - Поле ввода (композер)
    // Пока перевод не подтверждён (кнопка «Далее», галочка сверху или Enter),
    // текст можно редактировать и полностью стереть крестиком. После
    // подтверждения поле очищается и фокус автоматически возвращается в него,
    // чтобы можно было сразу продолжать печатать следующий перевод, а
    // предыдущий остаётся в истории выше — там доступно только копирование.

    private var composer: some View {
        VStack(spacing: 10) {
            // Исходный текст
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("", selection: $vm.sourceLanguage) {
                        ForEach(supportedLanguages, id: \.self) { lang in
                            Text(languageAutonym(lang)).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline.weight(.semibold))
                    .labelsHidden()

                    Spacer()

                    if !vm.sourceText.isEmpty {
                        Button {
                            vm.clearInput()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("Введите текст", text: $vm.sourceText, axis: .vertical)
                    .font(.title3)
                    .focused($focused)
                    .lineLimit(1...6)
                    .onChange(of: vm.sourceText) { _ in
                        vm.beginTyping()
                    }
                    .onSubmit { finalizeAndKeepEditing() }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Button { vm.swapLanguages() } label: {
                Image(systemName: "arrow.up.arrow.down.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)

            // Перевод (превью)
            VStack(alignment: .leading, spacing: 6) {
                Text(languageAutonym(vm.targetLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Text(vm.preview.isEmpty ? "Enter text" : vm.preview)
                    .font(.title3)
                    .foregroundStyle(vm.preview.isEmpty ? Color.secondary : Color.accentColor)

                if !vm.preview.isEmpty {
                    HStack {
                        Spacer()
                        Button { UIPasteboard.general.string = vm.preview } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Spacer()
                Button("Далее") { finalizeAndKeepEditing() }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.preview.isEmpty)
            }
        }
        .padding()
    }

    private func finalizeAndKeepEditing() {
        vm.finalize()
        focused = true
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble").font(.system(size: 36)).foregroundStyle(.secondary)
            Text(vm.isModelInstalled ? "Начните печатать, чтобы перевести текст" : "Скачайте модель выше, чтобы начать переводить офлайн")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct TranslationCard: View {
    let item: TranslationItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.source).font(.body)
            Divider()
            HStack { Text(item.translated).font(.body); Spacer(); Button { UIPasteboard.general.string = item.translated } label: { Image(systemName: "doc.on.doc") } }
            Text("\(languageAutonym(item.sourceLang)) → \(languageAutonym(item.targetLang))").font(.caption).foregroundStyle(.secondary)
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
