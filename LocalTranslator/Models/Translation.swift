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

/// Название языка на нём самом  (автоним), для отображения в выборе языка.
/// Внутренний идентификатор языка (переданный в `supportedLanguages` и используемый
/// сервисом перевода) при этом не меняется — меняется только то, что видит пользователь.
private let languageAutonyms: [String: String] = [
    "English": "English",
    "Russian": "Русский",
    "German": "Deutsch",
    "French": "Français",
    "Spanish": "Español",
    "Italian": "Italiano",
    "Portuguese": "Português",
    "Chinese": "中文",
    "Japanese": "日本語",
    "Korean": "한국어",
    "Arabic": "العربية",
    "Turkish": "Türkçe",
    "Dutch": "Nederlands",
    "Polish": "Polski",
    "Ukrainian": "Українська",
    "Vietnamese": "Tiếng Việt",
    "Thai": "ไทย",
    "Indonesian": "Bahasa Indonesia",
    "Malay": "Bahasa Melayu",
    "Hindi": "हिन्दी",
    "Bengali": "বাংলা",
    "Persian": "فارسی",
    "Hebrew": "עברית",
    "Czech": "Čeština",
    "Greek": "Ελληνικά",
    "Romanian": "Română",
    "Hungarian": "Magyar",
    "Swedish": "Svenska",
    "Danish": "Dansk",
    "Finnish": "Suomi",
    "Norwegian": "Norsk",
    "Slovak": "Slovenčina",
    "Bulgarian": "Български"
]

func languageAutonym(_ language: String) -> String {
    languageAutonyms[language] ?? language
}
