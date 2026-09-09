import SwiftUI

@main
struct LocalTranslatorApp: App {
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("theme") private var theme = "system"
    @StateObject private var viewModel = TranslatorViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingCompleted { TranslationView() } else { OnboardingView() }
            }
            .environmentObject(viewModel)
            .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
    }
}
