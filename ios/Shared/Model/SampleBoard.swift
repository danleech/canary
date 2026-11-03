import Foundation

/// A small built-in board for widget placeholders and SwiftUI previews.
/// It is illustrative only and never shown as real data.
public enum SampleBoard {
    public static let board: Board = {
        let status = Data(statusJSON.utf8)
        let history = Data(historyJSON.utf8)
        guard let board = try? CanaryClient.makeBoard([.status: status, .history: history], fetchedAt: .now) else {
            fatalError("SampleBoard JSON is invalid")
        }
        return board
    }()

    private static let statusJSON = """
    {"version":"1.2","as_of":"2026-11-03T18:02:27Z","valid_until":"2099-01-01T00:00:00Z",
     "next_run":"2026-11-03T23:40:00Z","headline":"Sample board for previews.",
     "world":{"score":41,"band":"Strained","counts":{"alert":18,"watch":39,"normal":32},
              "by_domain":{"markets":23,"energy":75}},
     "situations":[],"emerging":[],
     "signals":[
      {"id":"oil","name":"Brent crude","domain":"energy","domain_name":"Energy & Commodities",
       "status":"alert","trend":"stable","horizon":"acute","value":"Brent $104","value_num":104,
       "summary":"Sample summary","situations":[],"basis":"measured","sources":[],
       "url":"https://canary.danleech.com/s/oil"},
      {"id":"equity-stress","name":"US equity stress","domain":"markets","domain_name":"Markets",
       "status":"watch","trend":"worsening","horizon":"acute","value":"VIX 20.8","value_num":20.8,
       "summary":"Sample summary","situations":[],"basis":"measured","sources":[],
       "url":"https://canary.danleech.com/s/equity-stress"},
      {"id":"ftse","name":"FTSE 100","domain":"markets","domain_name":"Markets",
       "status":"normal","trend":"stable","horizon":"acute","value":"10,761","value_num":10761,
       "summary":"Sample summary","situations":[],"basis":"measured","sources":[],
       "url":"https://canary.danleech.com/s/ftse"}
     ]}
    """

    private static let historyJSON = """
    {"oil":[["2026-11-01T05:43:22Z","a",96],["2026-11-02T05:51:55Z","r",101],["2026-11-03T05:51:01Z","r",104]],
     "equity-stress":[["2026-11-01T05:43:22Z","g",18.9],["2026-11-02T05:51:55Z","g",19.4],["2026-11-03T05:51:01Z","a",20.8]],
     "ftse":[["2026-11-01T05:43:22Z","g",10730],["2026-11-02T05:51:55Z","g",10745],["2026-11-03T05:51:01Z","g",10761]]}
    """
}
