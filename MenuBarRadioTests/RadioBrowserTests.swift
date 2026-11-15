import Foundation
import Testing
@testable import MenuBarRadio

struct RadioBrowserTests {
    private let baseURL = URL(string: "https://de1.api.radio-browser.info")!

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func emptySearchRequestsTopVotedStations() throws {
        let request = try RadioBrowserDirectoryProvider.makeRequest(
            query: RadioDirectorySearchQuery(limit: 500), baseURL: baseURL
        )
        #expect(request.url?.host == "de1.api.radio-browser.info")
        #expect(request.url?.path == "/json/stations/topvote/100")
        #expect(queryItems(request)["hidebroken"] == "true")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == AppInfo.userAgent)
    }

    @Test func textSearchIncludesFilters() throws {
        let query = RadioDirectorySearchQuery(text: " Rock & Roll ", countryCode: "de", tag: "rock", limit: 10, hideBroken: false)
        let request = try RadioBrowserDirectoryProvider.makeRequest(query: query, baseURL: baseURL)
        let items = queryItems(request)

        #expect(request.url?.path == "/json/stations/search")
        #expect(items["name"] == "Rock & Roll")
        #expect(items["countrycode"] == "DE")
        #expect(items["tag"] == "rock")
        #expect(items["limit"] == "10")
        #expect(items["hidebroken"] == "false")
    }

    @Test func decodesStationsLeniently() throws {
        let json = """
        [{"stationuuid":"1","name":"Radio Bob","url":"http://a","url_resolved":"https://b",
          "homepage":"https://bob.de","favicon":"","tags":"rock","country":"Germany","countrycode":"DE",
          "state":"","language":"german","languagecodes":"de","geo_lat":"50.1","geo_long":8,
          "codec":"MP3","bitrate":"128","votes":42,"lastcheckok":1},
         {"stationuuid":"2","name":"   ","url":"http://c"}]
        """
        let stations = try RadioBrowserDirectoryProvider.decodeStations(from: Data(json.utf8))

        #expect(stations.count == 1)
        let station = try #require(stations.first)
        #expect(station.preferredStreamURL?.absoluteString == "https://b")
        #expect(station.bitrate == 128)
        #expect(station.geoLatitude == 50.1)
        #expect(station.geoLongitude == 8)
        #expect(station.lastCheckOK)
    }

    @Test func parsesAndDeduplicatesServerList() {
        let json = """
        [{"ip":"91.98.4.78","name":"de1.api.radio-browser.info"},
         {"ip":"2a01:4f8::1","name":"DE1.api.radio-browser.info"},
         {"ip":"1.2.3.4","name":"fi1.api.radio-browser.info"},
         {"ip":"6.6.6.6","name":"evil.example.com"}]
        """
        #expect(RadioBrowserServerPool.hostNames(fromServerList: Data(json.utf8))
                == ["de1.api.radio-browser.info", "fi1.api.radio-browser.info"])
        #expect(RadioBrowserServerPool.hostNames(fromServerList: Data("garbage".utf8)).isEmpty)
    }

    @Test func ranksPreferredFirstAndRecentlyFailedLast() {
        let now = Date()
        let ranked = RadioBrowserServerPool.rank(
            ["a", "b", "c", "d"],
            preferred: "c",
            failedAt: ["a": now.addingTimeInterval(-60), "d": now.addingTimeInterval(-3600)],
            now: now,
            penalty: 600
        )
        // "d" failed long ago and is healthy again; "a" failed recently.
        #expect(ranked == ["c", "b", "d", "a"])
    }

    @Test func runsInsideTestHostWithoutStartingThePlayer() {
        #expect(AppEntry.isRunningTests)
    }
}
