import Foundation

enum LyricsLoadState: Equatable {
    case empty
    case loading
    case ready
    case unavailable
    case instrumental
}

struct SyncedLyricLine: Identifiable, Codable, Equatable {
    let id: Int
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let text: String
}

struct LyricsSnapshot: Equatable {
    static let empty = LyricsSnapshot(
        trackKey: "",
        state: .empty,
        plainLyrics: "",
        syncedLines: [],
        source: nil,
        fetchedAt: nil
    )

    let trackKey: String
    let state: LyricsLoadState
    let plainLyrics: String
    let syncedLines: [SyncedLyricLine]
    let source: String?
    let fetchedAt: Date?

    var hasSyncedLyrics: Bool {
        !syncedLines.isEmpty
    }

    var hasAnyLyrics: Bool {
        hasSyncedLyrics || !plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LyricsTrackRequest: Hashable {
    let bundleIdentifier: String?
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval

    var cacheKey: String {
        [
            normalized(title),
            normalized(artist),
            normalized(album),
            duration > 0 ? String(Int(duration.rounded())) : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "|")
    }

    var searchQuery: String {
        [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

actor LyricsService {
    static let shared = LyricsService()

    private let session: URLSession
    private var memoryCache: [String: LyricsSnapshot] = [:]
    private let cacheDirectory: URL
    private let cacheTTL: TimeInterval = 60 * 60 * 24 * 14

    private init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = caches
            .appendingPathComponent("QuartzNotch", isDirectory: true)
            .appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedSnapshot(for request: LyricsTrackRequest) -> LyricsSnapshot? {
        if let cached = memoryCache[request.cacheKey], !isExpired(cached) {
            guard cached.state != .unavailable else { return nil }
            return cached
        }

        guard let disk = readDiskCache(for: request.cacheKey), !isExpired(disk) else {
            return nil
        }
        guard disk.state != .unavailable else { return nil }
        memoryCache[request.cacheKey] = disk
        return disk
    }

    func fetchSnapshot(for request: LyricsTrackRequest, plainFallback: String?) async -> LyricsSnapshot {
        if let cached = cachedSnapshot(for: request) {
            return cached
        }

        if let remote = await fetchFromLRCLIB(request: request) {
            memoryCache[request.cacheKey] = remote
            writeDiskCache(remote, for: request.cacheKey)
            return remote
        }

        let fallback = plainFallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state: LyricsLoadState = fallback.isEmpty ? .unavailable : .ready
        let snapshot = LyricsSnapshot(
            trackKey: request.cacheKey,
            state: state,
            plainLyrics: fallback,
            syncedLines: [],
            source: fallback.isEmpty ? nil : "Apple Music",
            fetchedAt: Date()
        )
        if snapshot.hasAnyLyrics || snapshot.state == .instrumental {
            memoryCache[request.cacheKey] = snapshot
            writeDiskCache(snapshot, for: request.cacheKey)
        }
        return snapshot
    }

    private func fetchFromLRCLIB(request: LyricsTrackRequest) async -> LyricsSnapshot? {
        if let exact = await fetchExactFromLRCLIB(request: request) {
            return exact
        }

        if let fieldSearch = await searchLRCLIB(request: request, queryItems: [
            URLQueryItem(name: "track_name", value: request.title),
            URLQueryItem(name: "artist_name", value: request.artist)
        ]) {
            return fieldSearch
        }

        return await searchLRCLIB(request: request, queryItems: [
            URLQueryItem(name: "q", value: request.searchQuery)
        ])
    }

    private func fetchExactFromLRCLIB(request: LyricsTrackRequest) async -> LyricsSnapshot? {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(string: "https://lrclib.net/api/get") else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "track_name", value: request.title),
            URLQueryItem(name: "artist_name", value: request.artist)
        ]
        if !request.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: request.album))
        }
        if request.duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(request.duration.rounded()))))
        }
        components.queryItems = queryItems

        guard let data = await fetchData(from: components.url) else { return nil }
        guard let result = try? JSONDecoder().decode(LRCLIBResult.self, from: data) else { return nil }
        return snapshot(from: result, request: request)
    }

    private func searchLRCLIB(request: LyricsTrackRequest, queryItems: [URLQueryItem]) async -> LyricsSnapshot? {
        guard !request.searchQuery.isEmpty,
              var components = URLComponents(string: "https://lrclib.net/api/search") else {
            return nil
        }

        components.queryItems = queryItems
        guard let data = await fetchData(from: components.url),
              let results = try? JSONDecoder().decode([LRCLIBResult].self, from: data),
              let best = bestResult(in: results, for: request) else {
            return nil
        }

        return snapshot(from: best, request: request)
    }

    private func fetchData(from url: URL?) async -> Data? {
        guard let url else { return nil }
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 12
        urlRequest.setValue("QuartzNotch/1.0 (https://github.com/Clayton630/QuartzNotch)", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func snapshot(from result: LRCLIBResult, request: LyricsTrackRequest) -> LyricsSnapshot? {
        if result.instrumental == true {
            return LyricsSnapshot(
                trackKey: request.cacheKey,
                state: .instrumental,
                plainLyrics: "",
                syncedLines: [],
                source: "LRCLIB",
                fetchedAt: Date()
            )
        }

        let synced = result.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plain = result.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lines = LRCParser.parse(synced)
        guard !lines.isEmpty || !plain.isEmpty else { return nil }

        return LyricsSnapshot(
            trackKey: request.cacheKey,
            state: .ready,
            plainLyrics: plain.isEmpty ? LRCParser.plainText(from: lines) : plain,
            syncedLines: lines,
            source: "LRCLIB",
            fetchedAt: Date()
        )
    }

    private func bestResult(in results: [LRCLIBResult], for request: LyricsTrackRequest) -> LRCLIBResult? {
        let viable = results.filter {
            ($0.instrumental == true)
                || (($0.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    || ($0.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false))
        }
        guard !viable.isEmpty else { return nil }

        return viable.max { lhs, rhs in
            score(lhs, request: request) < score(rhs, request: request)
        }
    }

    private func score(_ result: LRCLIBResult, request: LyricsTrackRequest) -> Double {
        let titleScore = similarity(result.trackName ?? result.name ?? "", request.title)
        let artistScore = similarity(result.artistName ?? "", request.artist)
        let albumScore = request.album.isEmpty ? 0.0 : similarity(result.albumName ?? "", request.album)
        let durationScore: Double = {
            guard request.duration > 0, let duration = result.duration, duration > 0 else { return 0 }
            let delta = abs(duration - request.duration)
            if delta <= 2 { return 18 }
            if delta <= 5 { return 10 }
            if delta <= 10 { return 4 }
            return -min(delta, 30)
        }()
        let syncedBonus = (result.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 22.0 : 0.0
        let instrumentalPenalty = result.instrumental == true ? -8.0 : 0.0

        return (titleScore * 0.50) + (artistScore * 0.34) + (albumScore * 0.08) + durationScore + syncedBonus + instrumentalPenalty
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalizedForMatch(lhs)
        let b = normalizedForMatch(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 100 }
        if a.contains(b) || b.contains(a) { return 88 }

        let aTokens = Set(a.split(separator: " ").map(String.init))
        let bTokens = Set(b.split(separator: " ").map(String.init))
        guard !aTokens.isEmpty, !bTokens.isEmpty else { return 0 }
        let overlap = Double(aTokens.intersection(bTokens).count)
        let union = Double(aTokens.union(bTokens).count)
        return (overlap / union) * 100
    }

    private func normalizedForMatch(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\([^)]*feat[^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isExpired(_ snapshot: LyricsSnapshot) -> Bool {
        guard let fetchedAt = snapshot.fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > cacheTTL
    }

    private func cacheURL(for key: String) -> URL {
        let encoded = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return cacheDirectory.appendingPathComponent(encoded).appendingPathExtension("json")
    }

    private func readDiskCache(for key: String) -> LyricsSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL(for: key)),
              let payload = try? JSONDecoder().decode(CachedLyricsSnapshot.self, from: data) else {
            return nil
        }
        return payload.snapshot
    }

    private func writeDiskCache(_ snapshot: LyricsSnapshot, for key: String) {
        let payload = CachedLyricsSnapshot(snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheURL(for: key), options: .atomic)
    }
}

private struct CachedLyricsSnapshot: Codable {
    let trackKey: String
    let state: String
    let plainLyrics: String
    let syncedLines: [SyncedLyricLine]
    let source: String?
    let fetchedAt: Date?

    init(snapshot: LyricsSnapshot) {
        self.trackKey = snapshot.trackKey
        self.state = snapshot.state.cacheValue
        self.plainLyrics = snapshot.plainLyrics
        self.syncedLines = snapshot.syncedLines
        self.source = snapshot.source
        self.fetchedAt = snapshot.fetchedAt
    }

    var snapshot: LyricsSnapshot {
        LyricsSnapshot(
            trackKey: trackKey,
            state: LyricsLoadState(cacheValue: state),
            plainLyrics: plainLyrics,
            syncedLines: syncedLines,
            source: source,
            fetchedAt: fetchedAt
        )
    }
}

private extension LyricsLoadState {
    var cacheValue: String {
        switch self {
        case .empty: return "empty"
        case .loading: return "loading"
        case .ready: return "ready"
        case .unavailable: return "unavailable"
        case .instrumental: return "instrumental"
        }
    }

    init(cacheValue: String) {
        switch cacheValue {
        case "ready": self = .ready
        case "unavailable": self = .unavailable
        case "instrumental": self = .instrumental
        case "loading": self = .loading
        default: self = .empty
        }
    }
}

private struct LRCLIBResult: Decodable {
    let id: Int?
    let name: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum LRCParser {
    private static let timestampPattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#

    static func parse(_ lrc: String) -> [SyncedLyricLine] {
        guard !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }

        var entries: [(time: TimeInterval, text: String)] = []
        let normalized = lrc.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        for rawLine in normalized.components(separatedBy: "\n") {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: fullRange)
            guard !matches.isEmpty else { continue }

            let textStart = matches.last.map { $0.range.location + $0.range.length } ?? 0
            let text = nsLine.substring(from: min(textStart, nsLine.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for match in matches {
                if let time = timestamp(from: match, in: nsLine) {
                    entries.append((time, text))
                }
            }
        }

        let sorted = entries
            .filter { $0.time.isFinite && $0.time >= 0 }
            .sorted { lhs, rhs in
                if lhs.time == rhs.time { return lhs.text < rhs.text }
                return lhs.time < rhs.time
            }

        return sorted.enumerated().map { index, entry in
            let end = sorted.indices.contains(index + 1) ? sorted[index + 1].time : nil
            return SyncedLyricLine(
                id: index,
                startTime: entry.time,
                endTime: end,
                text: entry.text
            )
        }
    }

    static func plainText(from lines: [SyncedLyricLine]) -> String {
        lines
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func timestamp(from match: NSTextCheckingResult, in line: NSString) -> TimeInterval? {
        guard match.numberOfRanges >= 3 else { return nil }
        let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0

        var fraction = 0.0
        let fractionRange = match.range(at: 3)
        if fractionRange.location != NSNotFound {
            let raw = line.substring(with: fractionRange)
            let denominator = pow(10.0, Double(raw.count))
            fraction = (Double(raw) ?? 0) / denominator
        }

        return (minutes * 60) + seconds + fraction
    }
}
