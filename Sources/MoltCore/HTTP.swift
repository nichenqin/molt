import Foundation

public struct HTTPResponse: Sendable {
    public var status: Int
    public var data: Data
    public var headers: [String: String]
    public var finalURL: URL

    public init(status: Int, data: Data, headers: [String: String] = [:], finalURL: URL) {
        self.status = status
        self.data = data
        self.headers = headers
        self.finalURL = finalURL
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
    public var text: String { String(decoding: data, as: UTF8.self) }

    public func jsonObject() -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    public var etag: String? {
        headers.first { $0.key.lowercased() == "etag" }?.value
    }

    public var lastModified: String? {
        headers.first { $0.key.lowercased() == "last-modified" }?.value
    }
}

public protocol HTTPGetting: Sendable {
    func get(
        _ url: URL,
        headers: [String: String],
        timeout: TimeInterval,
        method: String
    ) async throws -> HTTPResponse
}

extension HTTPGetting {
    public func get(_ url: URL, timeout: TimeInterval = 15) async throws -> HTTPResponse {
        try await get(url, headers: [:], timeout: timeout, method: "GET")
    }

    public func head(_ url: URL, timeout: TimeInterval = 15) async throws -> HTTPResponse {
        try await get(url, headers: [:], timeout: timeout, method: "HEAD")
    }
}

public enum HTTPError: LocalizedError {
    case invalidResponse(URL)
    case status(Int, URL)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let url): "No HTTP response from \(url.host ?? url.absoluteString)"
        case .status(let code, let url): "HTTP \(code) from \(url.host ?? url.absoluteString)"
        }
    }
}

public final class URLSessionHTTPClient: HTTPGetting, @unchecked Sendable {
    private let session: URLSession
    private let userAgent: String

    public init(
        userAgent: String = "Molt/0.1 (+https://github.com/nichenqin/molt)",
        configuration: URLSessionConfiguration? = nil
    ) {
        let config = configuration ?? .default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate, br"]
        self.session = URLSession(configuration: config)
        self.userAgent = userAgent
    }

    public func get(
        _ url: URL,
        headers: [String: String],
        timeout: TimeInterval,
        method: String
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/json,application/xml,text/xml,*/*;q=0.8",
            forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse(url)
        }
        var normalized: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            normalized[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(
            status: http.statusCode,
            data: data,
            headers: normalized,
            finalURL: http.url ?? url
        )
    }
}
