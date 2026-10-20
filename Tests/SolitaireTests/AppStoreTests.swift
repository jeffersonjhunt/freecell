import Foundation
import Testing
@testable import Solitaire

/// What App Store Connect checks on upload, checked in the built app instead (the unit tests run
/// inside it): a missing privacy manifest or Info.plist key would otherwise surface only as a
/// rejected upload or a stalled TestFlight build.
@Suite struct AppStore {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test func declaresNoNonExemptEncryption() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test func hasAVersionAndACategory() {
        #expect(info["CFBundleShortVersionString"] as? String == "1.1")
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.card-games")
    }

    @Test func privacyManifestDeclaresOnlyItsOwnSettings() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                               "PrivacyInfo.xcprivacy must be in the app bundle")
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
                                 as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let apis = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(apis.count == 1)
        #expect(apis.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(apis.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
