import Foundation

@MainActor
struct AppSettings {
    @UserDefault(key: "com.tovam.MMTMR.settings.showControlStrip", defaultValue: false)
    static var showControlStripState: Bool
    
    @UserDefault(key: "com.tovam.MMTMR.settings.hapticFeedback", defaultValue: true)
    static var hapticFeedbackState: Bool
    
    @UserDefault(key: "com.tovam.MMTMR.settings.multitouchGestures", defaultValue: true)
    static var multitouchGestures: Bool
    
    @UserDefault(key: "com.tovam.MMTMR.blackListedApps", defaultValue: [])
    static var blacklistedAppIds: [String]
    
    @UserDefault(key: "com.tovam.MMTMR.dock.persistent", defaultValue: [])
    static var dockPersistentAppIds: [String]

    @UserDefault(key: "com.tovam.MMTMR.editor.port", defaultValue: 8787)
    static var editorPort: Int
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    var wrappedValue: T {
        get {
            return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }
}
