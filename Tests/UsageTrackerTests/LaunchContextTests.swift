import AppKit
import Testing
@testable import UsageTracker

@Suite struct LaunchContextTests {
    private func openEvent(propData: OSType?) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        if let propData {
            event.setParam(NSAppleEventDescriptor(enumCode: propData), forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    @Test func loginItemMarkerIsRecognised() {
        #expect(LaunchContext.isLoginItemLaunch(event: openEvent(propData: OSType(keyAELaunchedAsLogInItem))))
    }

    @Test func plainOpenAndMissingEventAreUserLaunches() {
        #expect(!LaunchContext.isLoginItemLaunch(event: openEvent(propData: nil)))
        #expect(!LaunchContext.isLoginItemLaunch(event: openEvent(propData: OSType(keyAELaunchedAsServiceItem))))
        #expect(!LaunchContext.isLoginItemLaunch(event: nil))
    }
}
