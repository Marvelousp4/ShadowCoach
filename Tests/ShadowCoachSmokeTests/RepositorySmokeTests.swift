import Foundation
import XCTest

final class RepositorySmokeTests: XCTestCase {
    func testExampleProviderConfigContainsNoCredentialValues() throws {
        let root = repositoryRoot()
        let data = try Data(contentsOf: root.appendingPathComponent("config/provider-config.example.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let azure = try XCTUnwrap(object["azure"] as? [String: Any])

        XCTAssertEqual(azure["speech_key"] as? String, "")
        XCTAssertEqual(azure["translator_key"] as? String, "")
    }

    func testPublicRepositoryDoesNotContainPersonalRuntimeData() {
        let root = repositoryRoot()
        let forbidden = [
            "provider-config.json",
            "ShadowCoachMobileDocuments",
            "ShadowCoach-iPhone-MVP-3Sources.shadowcoachbundle"
        ]

        for name in forbidden {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
