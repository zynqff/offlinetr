import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @AppStorage("theme") private var theme = "system"
    @AppStorage("idleTimeout") private var idleTimeout = 180
    var body: some View {
        NavigationStack {
            Form {
                Section("Модель") {
                    Text(vm.config?.model.id ?? "—")
                    Text("Версия: \(vm.config?.model.version ?? "—")")
                    Text("Размер: \(ByteCountFormatter.string(fromByteCount: vm.config?.model.sizeBytes ?? 0, countStyle: .file))")
                    Button("Проверить обновления") { Task { await vm.refreshConfig() } }
                    Button("Удалить модель", role: .destructive) { Task { await vm.deleteModel() } }
                }
                Section("Автовыгрузка") {
                    Picker("Таймаут", selection: $idleTimeout) { Text("30 сек").tag(30); Text("60 сек").tag(60); Text("3 мин").tag(180); Text("5 мин").tag(300); Text("10 мин").tag(600) }
                    Text("Модель выгружается при уходе приложения в фон независимо от таймаута.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Тема") {
                    Picker("Оформление", selection: $theme) { Text("Системная").tag("system"); Text("Светлая").tag("light"); Text("Тёмная").tag("dark") }
                }
                Section { Button("Показать обучение заново") { UserDefaults.standard.set(false, forKey: "onboardingCompleted") } }
            }.navigationTitle("Настройки")
        }
    }
}
