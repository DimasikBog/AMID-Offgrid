import SwiftUI

struct PocketGuide: Decodable {
    struct Item: Decodable, Identifiable { let id: String; let title: String }
    struct Card: Decodable, Identifiable { let id: String; let title: String; let body: String }
    let checklist: [Item]
    let cards: [Card]
}

@main
struct AMIDPocketApp: App {
    var body: some Scene { WindowGroup { PocketView() } }
}

struct PocketView: View {
    @State private var guide: PocketGuide?
    @State private var message: String?
    @State private var checked: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if let guide {
                    Section("Мій список") {
                        ForEach(guide.checklist) { item in
                            Toggle(item.title, isOn: Binding(
                                get: { checked.contains(item.id) },
                                set: { value in
                                    if value { checked.insert(item.id) } else { checked.remove(item.id) }
                                    UserDefaults.standard.set(Array(checked), forKey: "preparation")
                                }))
                                .accessibilityIdentifier("check-\(item.id)")
                        }
                    }
                    Section("Короткі картки") {
                        ForEach(guide.cards) { card in
                            NavigationLink(card.title) {
                                ScrollView { Text(card.body).padding().accessibilityIdentifier("card-body") }
                                    .navigationTitle(card.title)
                            }
                            .accessibilityIdentifier("card-\(card.id)")
                        }
                    }
                } else { Text(message ?? "Відкриваю матеріали…") }
            }
            .navigationTitle("AMID Pocket")
            .tint(.mint)
            .task {
                do {
                    guard let url = Bundle.main.url(forResource: "cards", withExtension: "json") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    guide = try JSONDecoder().decode(PocketGuide.self, from: Data(contentsOf: url))
                    let allowed = Set(guide?.checklist.map(\.id) ?? [])
                    checked = Set(UserDefaults.standard.stringArray(forKey: "preparation") ?? []).intersection(allowed)
                } catch { message = "Не вдалося відкрити картки. Перевстанови перевірену збірку." }
            }
        }
    }
}
