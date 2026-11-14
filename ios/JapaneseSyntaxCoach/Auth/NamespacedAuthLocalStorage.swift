import Foundation
import Supabase

struct NamespacedAuthLocalStorage: AuthLocalStorage, Sendable {
    let namespace: String
    private let backing: any AuthLocalStorage
    private let encodedNamespace: String

    init(namespace: String, backing: any AuthLocalStorage) {
        precondition(!namespace.isEmpty, "Auth storage namespace must not be empty")
        self.namespace = namespace
        self.backing = backing
        self.encodedNamespace = Self.hex(namespace)
    }

    func store(key: String, value: Data) throws {
        try backing.store(key: storageKey(for: key), value: value)
    }

    func retrieve(key: String) throws -> Data? {
        try backing.retrieve(key: storageKey(for: key))
    }

    func remove(key: String) throws {
        try backing.remove(key: storageKey(for: key))
    }

    private func storageKey(for key: String) -> String {
        "supabase-auth-ns-v1:\(encodedNamespace):\(Self.hex(key))"
    }

    private static func hex(_ value: String) -> String {
        value.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
