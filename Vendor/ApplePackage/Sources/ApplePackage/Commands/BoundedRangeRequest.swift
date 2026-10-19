import Foundation

/// Abort non-206 responses at the headers so a server ignoring Range cannot
/// accidentally make the version browser download an entire IPA into memory.
final class BoundedRangeRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Response {
        let data: Data
        let total: Int64
    }
    private let range: Range<Int64>
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Response, Error>?
    private var cancelled = false
    private var body = Data()
    private var total: Int64 = 0
    private var redirects = 0

    private init(range: Range<Int64>) { self.range = range }

    static func fetch(url: URL, range: Range<Int64>, configuration: URLSessionConfiguration? = nil) async throws -> Response {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
              range.lowerBound >= 0, range.upperBound > range.lowerBound,
              range.upperBound - range.lowerBound <= Int64(RemoteIPAReader.directoryLimit) else { throw RemoteIPAReader.Failure.unsupportedRange }
        let loader = BoundedRangeRequest(range: range)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { loader.start(url: url, configuration: configuration, continuation: $0) }
        }, onCancel: { loader.cancel() })
    }

    private func start(url: URL, configuration: URLSessionConfiguration?, continuation: CheckedContinuation<Response, Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<Response, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        let cancelled = self.cancelled
        lock.unlock()
        session?.invalidateAndCancel()
        if cancelled { continuation?.resume(throwing: CancellationError()) }
        else { continuation?.resume(with: result) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 206,
              let parsed = Self.contentRange(response.value(forHTTPHeaderField: "Content-Range")),
              parsed.range == range,
              response.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) != false,
              response.expectedContentLength < 0 || response.expectedContentLength == range.upperBound - range.lowerBound else {
            completionHandler(.cancel)
            finish(.failure(RemoteIPAReader.Failure.unsupportedRange))
            return
        }
        total = parsed.total
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= Int(range.upperBound - range.lowerBound) - body.count else {
            finish(.failure(RemoteIPAReader.Failure.oversizedMetadata))
            return
        }
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        guard body.count == Int(range.upperBound - range.lowerBound), total >= range.upperBound else {
            finish(.failure(RemoteIPAReader.Failure.unsupportedRange)); return
        }
        finish(.success(Response(data: body, total: total)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil else {
            completionHandler(nil)
            finish(.failure(RemoteIPAReader.Failure.unsupportedRange))
            return
        }
        var request = request
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        completionHandler(request)
    }

    static func contentRange(_ value: String?) -> (range: Range<Int64>, total: Int64)? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let parts = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let total = Int64(parts[1]), total > 0 else { return nil }
        let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]),
              start >= 0, end >= start, end < total else { return nil }
        return (start..<(end + 1), total)
    }
}
