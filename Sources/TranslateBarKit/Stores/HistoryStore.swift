import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [TranslationEntry] = []

    private let defaults: UserDefaults
    private let key = "translation.history.v1"
    private let maxEntries = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func append(_ entry: TranslationEntry) {
        entries.removeAll { $0.sourceText == entry.sourceText && $0.source == entry.source && $0.target == entry.target }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    func remove(_ entry: TranslationEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TranslationEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
