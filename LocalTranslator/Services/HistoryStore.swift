import Foundation
import CoreData

final class HistoryStore {
    static let shared = HistoryStore()
    let container: NSPersistentContainer

    private init() {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "HistoryEntry"
        entity.managedObjectClassName = "NSManagedObject"
        let fields: [(String, NSAttributeType, Bool)] = [
            ("sourceText", .stringAttributeType, false), ("translatedText", .stringAttributeType, false),
            ("sourceLang", .stringAttributeType, false), ("targetLang", .stringAttributeType, false), ("timestamp", .dateAttributeType, false)
        ]
        entity.properties = fields.map { name, type, optional in
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type; a.isOptional = optional; return a
        }
        model.entities = [entity]
        container = NSPersistentContainer(name: "LocalTranslator", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: Self.storeURL())
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed: \(error)") }
        }
    }

    private static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("History.sqlite")
    }

    func add(_ item: TranslationItem) {
        let object = NSEntityDescription.insertNewObject(forEntityName: "HistoryEntry", into: container.viewContext)
        object.setValue(item.source, forKey: "sourceText")
        object.setValue(item.translated, forKey: "translatedText")
        object.setValue(item.sourceLang, forKey: "sourceLang")
        object.setValue(item.targetLang, forKey: "targetLang")
        object.setValue(item.date, forKey: "timestamp")
        try? container.viewContext.save()
    }
}
