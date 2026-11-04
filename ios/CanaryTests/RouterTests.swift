import XCTest
@testable import Canary

/// Folding and unfolding iPhone Duo moves Browse between one tab (tab bar) and
/// separate sidebar items. The open item and anything pushed on it must carry
/// across both ways.
@MainActor
final class RouterTests: XCTestCase {
    func testUnfoldMovesBrowseStackIntoSidebarItem() {
        let router = Router()
        router.tab = .browse
        router.browsePath = [.domain("energy"), .signal("oil")]

        router.adapt(usesSidebar: true)

        XCTAssertEqual(router.tab, .browseSection(.domain("energy")))
        XCTAssertEqual(router.sectionPaths[.domain("energy")], [.signal("oil")])
    }

    func testFoldMovesSidebarItemBackIntoBrowseStack() {
        let router = Router()
        router.tab = .browseSection(.domain("climate"))
        router.sectionPaths[.domain("climate")] = [.signal("global-temp")]

        router.adapt(usesSidebar: false)

        XCTAssertEqual(router.tab, .browse)
        XCTAssertEqual(router.browsePath, [.domain("climate"), .signal("global-temp")])
    }

    func testRoundTripKeepsState() {
        let router = Router()
        router.tab = .browse
        router.browsePath = [.situations, .situation("us-iran-war")]
        router.adapt(usesSidebar: true)
        router.adapt(usesSidebar: false)
        XCTAssertEqual(router.tab, .browse)
        XCTAssertEqual(router.browsePath, [.situations, .situation("us-iran-war")])
    }

    func testBrowseRootWithoutItemOpensAllSignalsInSidebar() {
        let router = Router()
        router.tab = .browse
        router.browsePath = []
        XCTAssertEqual(router.displayedTab(usesSidebar: true), .browseSection(.allSignals))
        router.adapt(usesSidebar: true)
        XCTAssertEqual(router.tab, .browseSection(.allSignals))
    }

    func testOtherTabsAreUnaffected() {
        let router = Router()
        router.tab = .changes
        router.adapt(usesSidebar: true)
        XCTAssertEqual(router.tab, .changes)
        router.adapt(usesSidebar: false)
        XCTAssertEqual(router.tab, .changes)
    }

    func testDomainDeepLinkOpensBrowse() {
        let router = Router()
        router.open(URL(string: "canary://domain/energy")!)
        XCTAssertEqual(router.tab, .browse)
        XCTAssertEqual(router.browsePath, [.domain("energy")])
        XCTAssertEqual(router.displayedTab(usesSidebar: true), .browseSection(.domain("energy")))
    }

    func testSignalDeepLinkOpensOnSummary() {
        let router = Router()
        router.tab = .changes
        router.open(URL(string: "canary://signal/oil")!)
        XCTAssertEqual(router.tab, .summary)
        XCTAssertEqual(router.summaryPath, [.signal("oil")])
    }

    func testWebsiteSignalLinkIsUnderstood() {
        XCTAssertEqual(DeepLink(url: URL(string: "https://canary.danleech.com/s/gold")!), .signal("gold"))
        XCTAssertEqual(DeepLink(url: URL(string: "canary://world")!), .world)
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/s/gold")!))
    }
}
