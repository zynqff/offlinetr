import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboardingCompleted") private var completed = false
    @State private var page = 0
    var body: some View {
        TabView(selection: $page) {
            OnboardPage(title: "Печатайте текст", text: "Перевод запускается локально на устройстве.", icon: "text.cursor").tag(0)
            OnboardPage(title: "Выберите языки", text: "Доступно 33 языка.", icon: "globe").tag(1)
            OnboardPage(title: "Перевод по мере ввода", text: "Нажмите «Далее» или Enter, чтобы зафиксировать карточку.", icon: "arrow.left.arrow.right").tag(2)
            OnboardPage(title: "Настройте выгрузку", text: "Модель выгружается из памяти при уходе приложения в фон и по таймауту.", icon: "memorychip").tag(3)
            VStack(spacing: 24) {
                Image(systemName: "paintbrush").font(.system(size: 54))
                Text("Тема").font(.largeTitle.bold())
                Text("Системная тема выбрана по умолчанию. Её можно изменить в настройках.").multilineTextAlignment(.center)
                Button("Начать") { completed = true }.buttonStyle(.borderedProminent)
            }.padding().tag(4)
        }
        .tabViewStyle(.page)
        .safeAreaInset(edge: .bottom) {
            if page < 4 { Button("Далее") { withAnimation { page += 1 } }.buttonStyle(.borderedProminent).padding() }
        }
    }
}

private struct OnboardPage: View {
    let title: String; let text: String; let icon: String
    var body: some View { VStack(spacing: 24) { Spacer(); Image(systemName: icon).font(.system(size: 54)); Text(title).font(.largeTitle.bold()); Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary); Spacer() }.padding() }
}
