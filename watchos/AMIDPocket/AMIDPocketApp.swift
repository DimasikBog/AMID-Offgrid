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
                            Button {
                                if checked.contains(item.id) {
                                    checked.remove(item.id)
                                } else {
                                    checked.insert(item.id)
                                }
                                UserDefaults.standard.set(Array(checked), forKey: "preparation")
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: checked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(checked.contains(item.id) ? Color.mint : Color.secondary)
                                        .accessibilityHidden(true)
                                    Text(item.title)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("check-\(item.id)")
                            .accessibilityLabel(item.title)
                            .accessibilityValue(checked.contains(item.id) ? "Виконано" : "Не виконано")
                            .accessibilityAddTraits(.isButton)
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
