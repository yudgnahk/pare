import Foundation

/// The VM-related Docker Desktop settings; nil means the key is absent and Docker uses its default.
public struct DockerVMSettings: Sendable, Equatable {
    public let memoryMiB: Int?
    public let resourceSaver: Bool?
    public let kubernetes: Bool?
    public let engine: String?

    public init(memoryMiB: Int?, resourceSaver: Bool?, kubernetes: Bool?, engine: String?) {
        self.memoryMiB = memoryMiB
        self.resourceSaver = resourceSaver
        self.kubernetes = kubernetes
        self.engine = engine
    }
}

/// Reads `settings-store.json` (PascalCase) and legacy `settings.json` (camelCase) loosely; any drift is nil.
public enum DockerDesktopSettingsParser {
    static let maxBytes = 1024 * 1024

    public static func parse(_ data: Data) -> DockerVMSettings? {
        guard data.count <= maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !object.isEmpty else { return nil }
        let keys = Dictionary(object.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        guard let memory = int(keys["memorymib"]),
              let saver = bool(keys["useresourcesaver"]),
              let kubernetes = bool(keys["kubernetesenabled"]),
              let engine = string(keys["enginetypemac"]) else { return nil }
        if let value = memory, value <= 0 { return nil }
        return DockerVMSettings(
            memoryMiB: memory, resourceSaver: saver, kubernetes: kubernetes, engine: engine
        )
    }

    // Outer nil = wrong type; inner nil = key absent.
    private static func bool(_ raw: Any?) -> Bool?? {
        guard let raw else { return .some(nil) }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return .some(number.boolValue)
    }

    private static func int(_ raw: Any?) -> Int?? {
        guard let raw else { return .some(nil) }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else { return nil }
        return .some(number.intValue)
    }

    private static func string(_ raw: Any?) -> String?? {
        guard let raw else { return .some(nil) }
        guard let text = raw as? String else { return nil }
        return .some(text)
    }
}
