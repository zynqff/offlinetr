import Foundation

struct TranslationItem: Identifiable, Equatable {
    let id = UUID()
    let source: String
    let translated: String
    let sourceLang: String
    let targetLang: String
    let date: Date
}

let supportedLanguages = [
    "English", "Russian", "German", "French", "Spanish", "Italian", "Portuguese", "Chinese", "Japanese", "Korean",
    "Arabic", "Turkish", "Dutch", "Polish", "Ukrainian", "Vietnamese", "Thai", "Indonesian", "Malay", "Hindi",
    "Bengali", "Persian", "Hebrew", "Czech", "Greek", "Romanian", "Hungarian", "Swedish", "Danish", "Finnish",
    "Norwegian", "Slovak", "Bulgarian"
]
