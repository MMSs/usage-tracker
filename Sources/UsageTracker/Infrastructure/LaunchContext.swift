import AppKit

/// Tells a launch requested by the user apart from one the login item made
/// at startup, so Settings opens only for the former.
enum LaunchContext {
    /// True when the open event that launched the app carries the
    /// login-item marker. Nil (no event) counts as a user launch.
    static func isLoginItemLaunch(event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication else {
            return false
        }

        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    @MainActor
    static var isLoginItemLaunch: Bool {
        isLoginItemLaunch(event: NSAppleEventManager.shared().currentAppleEvent)
    }
}
