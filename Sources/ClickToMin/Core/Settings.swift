import Foundation

public protocol SettingsStore: AnyObject {
    var enabled: Bool { get set }
    var iconHidden: Bool { get set }
}

public enum SettingsKeys {
    public static let enabled = "com.click-to-min.enabled"
    public static let iconHidden = "com.click-to-min.iconHidden"
    public static let hideAcknowledged = "com.click-to-min.hideAcknowledged"
}
