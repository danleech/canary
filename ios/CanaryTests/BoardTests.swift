import XCTest
@testable import Canary

/// Chart figures and withheld market data, from a small fixed board.
final class BoardTests: XCTestCase {
    private static let status = """
    {"as_of":"2026-11-03T18:00:00Z","world":{"score":41,"band":"Strained","by_domain":{"energy":75,"markets":23}},
     "situations":[],"emerging":[],
     "signals":[
      {"id":"oil","name":"Oil (Brent)","domain":"energy","status":"alert","value":"$104","value_num":104,
       "rubric_hit":"Brent $104 in band","basis_detail":"Brent $=104","basis":"measured","changed_at":"2026-11-01T06:00:00Z"},
      {"id":"temp","name":"Global temperature","domain":"climate","status":"watch","value":"+1.8°C","value_num":1.8,
       "basis":"measured","changed_at":"2026-11-02T06:00:00Z"},
      {"id":"vix-ish","name":"Equity stress","domain":"markets","status":"normal","value":"VIX 18","basis":"measured",
       "changed_at":"2026-11-03T06:00:00Z"}
     ]}
    """
    private static let history = """
    {"oil":[["2026-11-01T06:00:00Z","a",96],["2026-11-02T06:00:00Z","r",101],["2026-11-03T06:00:00Z","r",104]],
     "temp":[["2026-11-01T06:00:00Z","g",1.7],["2026-11-02T06:00:00Z","a",1.8],["2026-11-03T06:00:00Z","a",1.8]],
     "vix-ish":[["2026-11-01T06:00:00Z","a",22],["2026-11-02T06:00:00Z","g",19],["2026-11-03T06:00:00Z","g",18]]}
    """
    private static let catalogue = """
    {"domains":[{"id":"energy","name":"Energy"},{"id":"climate","name":"Climate"},{"id":"markets","name":"Markets"}],
     "signals":[{"id":"oil","name":"Oil","domain":"energy","metrics":["brent"]},
                {"id":"temp","name":"Temp","domain":"climate","metrics":["global_temp"]},
                {"id":"vix-ish","name":"VIX","domain":"markets","metrics":["new_feed"]}]}
    """
    private static let metrics = """
    {"metrics":{"brent":{"source":"Yahoo Finance"},"global_temp":{"source":"Climate Reanalyzer"},
                "new_feed":{"source":"A vendor","licence":"derived values only; raw series not republished (licence)"}}}
    """

    private func board(catalogue: String? = catalogue, metrics: String? = metrics) throws -> Board {
        var files: [CanaryClient.Resource: Data] = [.status: Data(Self.status.utf8), .history: Data(Self.history.utf8)]
        if let catalogue { files[.catalogue] = Data(catalogue.utf8) }
        if let metrics { files[.metrics] = Data(metrics.utf8) }
        return try CanaryClient.makeBoard(files, fetchedAt: .now)
    }

    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-11-03T18:00:00Z")!

    func testMovesByDay() throws {
        let moves = try board().dailyMoves(days: 7, now: now, calendar: london)
        XCTAssertEqual(moves.map(\.up).reduce(0, +), 2)   // oil watch→alert, temp normal→watch
        XCTAssertEqual(moves.map(\.down).reduce(0, +), 1) // vix-ish watch→normal
        XCTAssertEqual(moves.count, 3)                    // 1–3 Nov, nothing before the history
    }

    func testLevelMixByDay() throws {
        let mix = try board().dailyLevelMix(days: 7, now: now, calendar: london)
        let lastDay = mix.filter { london.isDate($0.day, inSameDayAs: now) }
        // History codes: r = Alert, a = Watch, g = Normal.
        XCTAssertEqual(lastDay.first { $0.level == .alert }?.count, 1)  // oil
        XCTAssertEqual(lastDay.first { $0.level == .watch }?.count, 1)  // temp
        XCTAssertEqual(lastDay.first { $0.level == .normal }?.count, 1) // vix-ish
    }

    func testLevelSpansMergeRepeatedChecks() throws {
        let spans = try board().levelSpans(for: "temp", now: now)
        XCTAssertEqual(spans.map(\.level), [.normal, .watch])
        XCTAssertEqual(spans.last?.end, now)
    }

    func testDomainScoresHighestFirst() throws {
        XCTAssertEqual(try board().domainScores.map(\.domain.id), ["energy", "markets"])
    }

    func testRestrictedFiguresAreWithheld() throws {
        let board = try board()
        // Yahoo source, and a licence note, both withhold; open data doesn't.
        for id in ["oil", "vix-ish"] {
            let signal = try XCTUnwrap(board.signal(id))
            XCTAssertTrue(signal.withholdsFigures, id)
            XCTAssertNil(signal.value, id)
            XCTAssertNil(signal.rubricHit, id)
            XCTAssertNil(signal.basisDetail, id)
            XCTAssertTrue(board.history(for: id).allSatisfy { $0.value == nil }, id)
            XCTAssertEqual(board.history(for: id).count, 3, "levels stay")
        }
        let open = try XCTUnwrap(board.signal("temp"))
        XCTAssertFalse(open.withholdsFigures)
        XCTAssertEqual(open.value, "+1.8°C")
        XCTAssertEqual(board.valueSeries(for: "temp").count, 3)
    }

    func testWithholdingHasABuiltInFloor() throws {
        // Without the catalogue and metrics, known restricted signals are still withheld.
        let board = try board(catalogue: nil, metrics: nil)
        XCTAssertTrue(try XCTUnwrap(board.signal("oil")).withholdsFigures)
        XCTAssertFalse(try XCTUnwrap(board.signal("temp")).withholdsFigures)
    }
}
