import Foundation
import SwiftUI

struct Contact: Identifiable, Codable, Hashable {
    let id: UUID
    var address: String
    var name: String
    var isFavorite: Bool
    var dateAdded: Date

    init(address: String, name: String = "", isFavorite: Bool = false) {
        self.id = UUID()
        self.address = address
        self.name = name.isEmpty ? String(address.prefix(8)) : name
        self.isFavorite = isFavorite
        self.dateAdded = Date()
    }

    var displayName: String {
        name.isEmpty ? truncatedAddress : name
    }

    var truncatedAddress: String {
        if address.count > 12 {
            return "\(address.prefix(6))...\(address.suffix(4))"
        }
        return address
    }
}

@MainActor
final class ContactsStore: ObservableObject {
    @Published var contacts: [Contact] = []

    private let saveKey = "AlgoChatContacts"

    init() {
        load()
    }

    // MARK: - Contact Management

    func add(address: String, name: String = "") {
        guard !contacts.contains(where: { $0.address == address }) else { return }
        let contact = Contact(address: address, name: name)
        contacts.append(contact)
        save()
    }

    func remove(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    func update(_ contact: Contact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
            save()
        }
    }

    func toggleFavorite(_ contact: Contact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index].isFavorite.toggle()
            save()
        }
    }

    func toggleFavorite(address: String) {
        if let index = contacts.firstIndex(where: { $0.address == address }) {
            contacts[index].isFavorite.toggle()
            save()
        } else {
            // Add as favorite if not in contacts
            var contact = Contact(address: address)
            contact.isFavorite = true
            contacts.append(contact)
            save()
        }
    }

    func contact(for address: String) -> Contact? {
        contacts.first { $0.address == address }
    }

    func isFavorite(address: String) -> Bool {
        contacts.first { $0.address == address }?.isFavorite ?? false
    }

    func rename(address: String, to name: String) {
        if let index = contacts.firstIndex(where: { $0.address == address }) {
            contacts[index].name = name
            save()
        } else {
            add(address: address, name: name)
        }
    }

    // MARK: - Sorted Access

    var favorites: [Contact] {
        contacts.filter { $0.isFavorite }.sorted { $0.name < $1.name }
    }

    var allSorted: [Contact] {
        contacts.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.name < rhs.name
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = decoded
        }
    }
}
