import Foundation
import ClickToMinCore

extension Notification.Name {
    static let settingsChanged = Notification.Name("com.click-to-min.settingsChanged")
}

final class UserDefaultsSettings: SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKeys.enabled: true,
            SettingsKeys.iconHidden: false,
            SettingsKeys.hideAcknowledged: false,
        ])
    }

    var enabled: Bool {
        get { defaults.bool(forKey: SettingsKeys.enabled) }
        set {
            defaults.set(newValue, forKey: SettingsKeys.enabled)
            NotificationCenter.default.post(name: .settingsChanged, object: self)
        }
    }

    var iconHidden: Bool {
        get { defaults.bool(forKey: SettingsKeys.iconHidden) }
        set {
            defaults.set(newValue, forKey: SettingsKeys.iconHidden)
            NotificationCenter.default.post(name: .settingsChanged, object: self)
        }
    }
}
