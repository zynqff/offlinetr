import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboardingCompleted") private var completed = false
    @State private var page = 0

    private let pages: [OnboardPageData] = [
        .init(
            image: "onboarding-type",
            title: "Печатайте текст",
            text: "Перевод запускается локально на устройстве. Ваши данные не покидают телефон."
        ),
        .init(
            image: "onboarding-languages",
            title: "Выберите языки",
            text: "Доступно 33 языка. Выберите исходный и целевой язык."
        ),
        .init(
            image: "onboarding-translate",
            title: "Перевод по мере ввода",
            text: "Нажмите «Далее» или Enter, чтобы зафиксировать карточку перевода."
        ),
        .init(
            image: "onboarding-unload",
            title: "Настройте выгрузку",
            text: "Модель выгружается из памяти в фоне и по таймауту."
        ),
        .init(
            image: "onboarding-theme",
            title: "Тема",
            text: "Выберите светлую, тёмную или системную тему по вашему вкусу."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardPage(data: pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            PageDots(count: pages.count, current: page)
                .padding(.top, 8)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    completed = true
                }
            } label: {
                Text(page < pages.count - 1 ? "Далее" : "Начать")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.49, green: 0.42, blue: 0.93), Color(red: 0.4, green: 0.32, blue: 0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
}

private struct OnboardPageData {
    let image: String
    let title: String
    let text: String
}

private struct OnboardPage: View {
    let data: OnboardPageData

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.49, green: 0.42, blue: 0.93).opacity(0.16), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 170
                        )
                    )
                    .frame(width: 300, height: 300)

                Image(data.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
            }

            VStack(spacing: 12) {
                Text(data.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(data.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color(red: 0.49, green: 0.42, blue: 0.93) : Color(.systemGray4))
                    .frame(width: index == current ? 20 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
