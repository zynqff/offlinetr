# LocalTranslator iOS — release source

Нативное iOS-приложение по ТЗ `TZ_local_translator_ios.md`.

## Важная схема конфигурации

В приложении есть **одна постоянная ссылка на конфиг**. URL модели в приложение не зашит.
Приложение получает `config.json` по `ConfigEndpoint.url`, а уже из JSON берет `model.url`.

Файл, который нужно изменить один раз:

`LocalTranslator/Services/AppConfig.swift`

Там:

```swift
static let url = URL(string: "https://REPLACE-ME.example/config.json")!
```

Замените только эту ссылку на вашу постоянную ссылку на конфиг.

Пример `config.json`:

```json
{
  "schemaVersion": 1,
  "app": {
    "minimumVersion": "1.0.0"
  },
  "model": {
    "id": "hy-mt2-1.8b-1.25bit",
    "version": "1.0.0",
    "fileName": "hy-mt2-1.8b-1.25bit.gguf",
    "sizeBytes": 440000000,
    "sha256": "",
    "url": "https://YOUR-HOST/model.gguf"
  }
}
```

**То есть да: ссылка приложения на конфиг всегда одна, а ссылку на GGUF можно менять удалённо через конфиг без выпуска новой версии приложения.**

## llama.cpp

ТЗ требует официальный `llama.cpp` SwiftUI/XCFramework путь. Репозиторий не вшит в этот архив, потому что XCFramework занимает сотни мегабайт и должен собираться под конкретную версию llama.cpp.

1. Откройте `LocalTranslator.xcodeproj` на Mac с Xcode.
2. Выполните `Scripts/bootstrap_llama.sh`.
3. Добавьте полученный `build-apple/llama.xcframework` в `Vendor/` проекта и в target `LocalTranslator`.
4. Соберите на реальном iPhone. Для simulator GPU Metal отключается в коде, как в официальном примере.

Скрипт фиксирует commit llama.cpp, чтобы релиз был воспроизводимым.

## Signing

Bundle ID в проекте: `com.example.LocalTranslator` — замените на свой перед архивированием.

Для App Store/TestFlight потребуется собственная Apple Developer Team и подпись. Для локальной установки можно использовать обычный provisioning через Xcode.
