import Foundation

/// Records per-track audio chunks by downloading the stream between metadata changes.
final class TrackRecordingManager: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let stateQueue = DispatchQueue(label: "MenuBarRadio.TrackRecordingManager")
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var currentFileURL: URL?
    private var currentTrackKey: String?
    private var currentStreamURL: URL?

    var isRecording: Bool {
        stateQueue.sync { task != nil }
    }

    func start(streamURL: URL, trackKey: String, displayName: String) {
        stateQueue.async {
            guard self.canRecord(url: streamURL) else { return }
            guard self.currentTrackKey != trackKey || self.currentStreamURL != streamURL else { return }
            self.stopInternal()

            self.currentTrackKey = trackKey
            self.currentStreamURL = streamURL

            NSLog("Starting recording for trackKey: \(trackKey), streamURL: \(streamURL)")
            self.resolveFinalURL(for: streamURL) { resolvedURL in
                guard let resolvedURL else {
                    self.stopInternal()
                    return
                }
                self.startDownload(resolvedURL: resolvedURL, displayName: displayName)
            }
        }
    }

    func stop() {
        stateQueue.async {
            self.stopInternal()
        }
    }

    private func stopInternal() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        try? fileHandle?.close()
        fileHandle = nil
        currentFileURL = nil
        currentTrackKey = nil
        currentStreamURL = nil
    }

    private func startDownload(resolvedURL: URL, displayName: String) {
        do {
            let outputURL = try makeOutputURL(for: displayName, streamURL: resolvedURL)
            currentFileURL = outputURL
            fileManager.createFile(atPath: outputURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: outputURL)

            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            task = session?.dataTask(with: resolvedURL)
            NSLog("Initiating download task for URL: \(resolvedURL) - outPath: \(outputURL.path)")
            task?.resume()
        } catch {
            stopInternal()
        }
    }

    private func resolveFinalURL(for url: URL, completion: @escaping (URL?) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let headSession = URLSession(configuration: config)

        let task = headSession.dataTask(with: request) { [weak self] _, response, _ in
            headSession.finishTasksAndInvalidate()
            let resolved = (response as? HTTPURLResponse)?.url ?? url
            if let self, !self.canRecord(url: resolved) {
                completion(nil)
            } else {
                completion(resolved)
            }
        }
        task.resume()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateQueue.async {
            do {
                try self.fileHandle?.write(contentsOf: data)
            } catch {
                self.stopInternal()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            self.stopInternal()
        }
    }

    // MARK: File naming

    private func makeOutputURL(for displayName: String, streamURL: URL) throws -> URL {
        let base = try recordingsDirectory()
        let datePrefix = Self.fileTimestamp.string(from: Date())
        let cleanedName = sanitize(displayName)
        let ext = fileExtension(for: streamURL)
        let filename = "\(datePrefix) - \(cleanedName).\(ext)"
        NSLog("Recording track to: \(filename)")
        return base.appendingPathComponent(filename)
    }

    private func recordingsDirectory() throws -> URL {
        let musicDir = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first
        let base = (musicDir ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Music"))
            .appendingPathComponent("MenuBarRadio")
        if !fileManager.fileExists(atPath: base.path) {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "aac" || ext == "mp3" {
            return ext
        }
        let lower = url.absoluteString.lowercased()
        if lower.contains("aac") {
            return "aac"
        }
        if lower.contains("mp3") {
            return "mp3"
        }
        return "audio"
    }

    private func sanitize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: " ")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Track" : trimmed
    }

    private static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private func canRecord(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let playlistExtensions: Set<String> = ["m3u", "m3u8", "pls", "asx", "xspf"]
        if playlistExtensions.contains(ext) { return false }
        let lower = url.absoluteString.lowercased()
        return !playlistExtensions.contains(where: { lower.contains(".\($0)") })
    }
}
