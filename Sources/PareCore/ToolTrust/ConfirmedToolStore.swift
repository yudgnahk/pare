import Foundation
import Security

/// Persists confirmed tools. A store that cannot be read means nothing is confirmed.
public protocol ConfirmedToolStoring: Sendable {
    func load() throws -> [ConfirmableTool: ConfirmedTool]
    func save(_ tools: [ConfirmableTool: ConfirmedTool]) throws
}

public struct KeychainStoreError: Error, Equatable {
    public let status: OSStatus
}

/// One generic-password item in the login keychain. Its default ACL trusts only the app that created it,
/// so other same-user code cannot read or rewrite it without a Keychain prompt, unlike a file in Application Support.
public struct KeychainConfirmedToolStore: ConfirmedToolStoring {
    static let service = "com.yudgnahk.pare.confirmed-tools"
    static let account = "developer-tools"
    static let label = "Pare confirmed developer tools"

    public init() {}

    public func load() throws -> [ConfirmableTool: ConfirmedTool] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainStoreError(status: status) }
        return try ConfirmedToolCoding.decode(data)
    }

    public func save(_ tools: [ConfirmableTool: ConfirmedTool]) throws {
        guard !tools.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainStoreError(status: status) }
            return
        }
        let data = try ConfirmedToolCoding.encode(tools)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainStoreError(status: update) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = Self.label
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStoreError(status: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }
}

/// For processes that must never run a third-party tool on their own (CLI, tests, snapshot runs).
public struct NoConfirmedToolStore: ConfirmedToolStoring {
    public init() {}
    public func load() throws -> [ConfirmableTool: ConfirmedTool] { [:] }
    public func save(_ tools: [ConfirmableTool: ConfirmedTool]) throws {}
}

enum ConfirmedToolCoding {
    static func encode(_ tools: [ConfirmableTool: ConfirmedTool]) throws -> Data {
        let keyed = Dictionary(uniqueKeysWithValues: tools.map { ($0.key.rawValue, $0.value) })
        return try JSONEncoder().encode(keyed)
    }

    /// Unknown tool names are dropped, not an error, so an older build can read a newer item.
    static func decode(_ data: Data) throws -> [ConfirmableTool: ConfirmedTool] {
        let keyed = try JSONDecoder().decode([String: ConfirmedTool].self, from: data)
        return Dictionary(uniqueKeysWithValues: keyed.compactMap { key, value in
            ConfirmableTool(rawValue: key).map { ($0, value) }
        })
    }
}
