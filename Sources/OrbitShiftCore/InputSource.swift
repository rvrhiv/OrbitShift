public struct InputSource: Identifiable, Equatable, Codable, Sendable {
  public var id: String
  public var name: String
  public var language: String
  public var isAvailable: Bool

  public init(id: String, name: String, language: String, isAvailable: Bool = true) {
    self.id = id
    self.name = name
    self.language = language
    self.isAvailable = isAvailable
  }
}

public enum InputSourceCycle {
  /// Always starts from the system's current source, including external changes.
  public static func next(currentID: String?, orderedIDs: [String], availableIDs: Set<String>)
    -> String?
  {
    var seen = Set<String>()
    let cycle = orderedIDs.filter { availableIDs.contains($0) && seen.insert($0).inserted }
    guard let first = cycle.first else { return nil }
    guard let currentID, let index = cycle.firstIndex(of: currentID) else { return first }
    guard cycle.count > 1 else { return nil }
    return cycle[(index + 1) % cycle.count]
  }
}

public struct Preferences: Codable, Sendable {
  public var schemaVersion = 1
  public var trigger: TriggerKey = .fn
  public var sourceIDs: [String]
  public var sourceNames: [String: String] = [:]
  public var isPaused = false

  public init(sourceIDs: [String]) { self.sourceIDs = sourceIDs }
}
