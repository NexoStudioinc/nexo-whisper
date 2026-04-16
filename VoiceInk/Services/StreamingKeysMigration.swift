import Foundation

/// One-time migration from legacy per-provider streaming UserDefaults keys
/// to the generic per-model key pattern ("streaming-enabled-{model.name}").
///
/// Safe to delete this file once all users have updated past this version.
enum StreamingKeysMigration {
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "streaming-keys-migrated") else { return }

        let legacyMappings: [(old: String, new: [String])] = [
            ("parakeet-streaming-enabled", [
                "streaming-enabled-parakeet-tdt-0.6b-v2",
                "streaming-enabled-parakeet-tdt-0.6b-v3",
            ]),
        ]

        for mapping in legacyMappings {
            if let value = defaults.object(forKey: mapping.old) as? Bool {
                for newKey in mapping.new {
                    defaults.set(value, forKey: newKey)
                }
                defaults.removeObject(forKey: mapping.old)
            }
        }

        defaults.set(true, forKey: "streaming-keys-migrated")
    }
}
