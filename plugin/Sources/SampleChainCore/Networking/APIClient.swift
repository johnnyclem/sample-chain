// APIClient.swift
// SampleChainCore
//
// Generic async/await API client built on URLSession for communicating with the SampleChain backend.

import Foundation

// MARK: - API Error

/// Errors that can occur during API communication.
public enum APIError: Error, LocalizedError, Sendable {
    /// The request URL could not be constructed.
    case invalidURL
    /// The request body could not be encoded.
    case encodingFailed(Error)
    /// The response body could not be decoded.
    case decodingFailed(Error)
    /// The server returned an HTTP error status code.
    case httpError(statusCode: Int, body: Data?)
    /// The request was cancelled or the network is unreachable.
    case networkError(Error)
    /// Authentication is required but no valid token is available.
    case unauthorized
    /// Rate limit exceeded; retry after the specified interval.
    case rateLimited(retryAfterSeconds: Int?)
    /// The server returned an application-level error in the response body.
    case serverError(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .encodingFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .httpError(let statusCode, _):
            return "HTTP error \(statusCode)."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required. Please sign in."
        case .rateLimited(let seconds):
            if let seconds {
                return "Rate limited. Retry after \(seconds) seconds."
            }
            return "Rate limited. Please try again later."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - HTTP Method

/// Supported HTTP methods.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Request

/// A type-safe description of an API request.
public struct APIRequest<Response: Decodable & Sendable>: Sendable {
    /// The endpoint path (appended to the base URL).
    public let path: String
    /// HTTP method.
    public let method: HTTPMethod
    /// Query parameters appended to the URL.
    public let queryItems: [URLQueryItem]?
    /// Request body (will be JSON-encoded).
    public let body: (any Encodable & Sendable)?
    /// Additional headers to include.
    public let headers: [String: String]?
    /// Whether this request requires authentication.
    public let requiresAuth: Bool

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable & Sendable)? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
        self.headers = headers
        self.requiresAuth = requiresAuth
    }
}

// MARK: - Paginated Response

/// Generic wrapper for paginated API responses.
public struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    /// The items on this page.
    public let items: [T]
    /// Total number of items across all pages.
    public let totalCount: Int
    /// Current page number (1-indexed).
    public let page: Int
    /// Number of items per page.
    public let pageSize: Int
    /// Whether more pages are available.
    public let hasNextPage: Bool

    public init(items: [T], totalCount: Int, page: Int, pageSize: Int, hasNextPage: Bool) {
        self.items = items
        self.totalCount = totalCount
        self.page = page
        self.pageSize = pageSize
        self.hasNextPage = hasNextPage
    }
}

// MARK: - API Client Configuration

/// Configuration for the API client.
public struct APIClientConfiguration: Sendable {
    /// Base URL for the SampleChain backend API.
    public let baseURL: URL
    /// Default timeout interval for requests in seconds.
    public let timeoutInterval: TimeInterval
    /// Maximum number of automatic retries for transient failures.
    public let maxRetries: Int

    public static let `default` = APIClientConfiguration(
        baseURL: URL(string: "https://api.samplechain.io/v1")!,
        timeoutInterval: 30,
        maxRetries: 3
    )

    public static let development = APIClientConfiguration(
        baseURL: URL(string: "http://localhost:3000/v1")!,
        timeoutInterval: 10,
        maxRetries: 1
    )

    public init(baseURL: URL, timeoutInterval: TimeInterval, maxRetries: Int) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
    }
}

// MARK: - Auth Token Provider

/// Protocol for providing authentication tokens to the API client.
public protocol AuthTokenProvider: Sendable {
    /// Returns the current auth token, refreshing if necessary.
    func currentToken() async throws -> String?
    /// Clears the stored token (e.g. on 401 response).
    func clearToken() async
}

// MARK: - API Client

/// The main API client for communicating with the SampleChain backend.
///
/// Uses `URLSession` with async/await. Supports automatic retries for transient
/// network errors, authentication header injection, and JSON encoding/decoding.
///
/// Usage:
/// ```swift
/// let client = APIClient()
/// let samples = try await client.execute(Endpoints.browseSamples(page: 1))
/// ```
public actor APIClient {
    private let session: URLSession
    private let configuration: APIClientConfiguration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var authTokenProvider: (any AuthTokenProvider)?

    public init(
        configuration: APIClientConfiguration = .default,
        authTokenProvider: (any AuthTokenProvider)? = nil
    ) {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeoutInterval
        sessionConfig.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "SampleChain-Plugin/1.0",
        ]
        self.session = URLSession(configuration: sessionConfig)
        self.configuration = configuration

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        self.authTokenProvider = authTokenProvider
    }

    /// Set or update the auth token provider.
    public func setAuthTokenProvider(_ provider: any AuthTokenProvider) {
        self.authTokenProvider = provider
    }

    /// Execute a typed API request and return the decoded response.
    ///
    /// - Parameter request: The API request descriptor.
    /// - Returns: The decoded response of type `Response`.
    /// - Throws: ``APIError`` on failure.
    public func execute<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response {
        let urlRequest = try await buildURLRequest(from: request)
        return try await performWithRetry(urlRequest: urlRequest, retriesRemaining: configuration.maxRetries)
    }

    /// Execute a request that returns no meaningful body (e.g. DELETE).
    public func executeVoid(_ request: APIRequest<EmptyResponse>) async throws {
        let urlRequest = try await buildURLRequest(from: request)
        let _: EmptyResponse = try await performWithRetry(urlRequest: urlRequest, retriesRemaining: configuration.maxRetries)
    }

    /// Upload a file with multipart/form-data encoding.
    ///
    /// - Parameters:
    ///   - path: The API endpoint path.
    ///   - fileURL: Local URL of the file to upload.
    ///   - fieldName: Form field name for the file (default: "file").
    ///   - additionalFields: Additional form fields to include.
    ///   - progressHandler: Callback for upload progress (0.0 to 1.0).
    /// - Returns: The decoded response.
    public func upload<Response: Decodable & Sendable>(
        path: String,
        fileURL: URL,
        fieldName: String = "file",
        additionalFields: [String: String] = [:],
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Response {
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Inject auth token if available
        if let token = try await authTokenProvider?.currentToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build multipart body
        var bodyData = Data()
        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let mimeType = "audio/wav" // Default; could be extended to detect from extension

        // Additional fields
        for (key, value) in additionalFields {
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            bodyData.append("\(value)\r\n".data(using: .utf8)!)
        }

        // File field
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        bodyData.append(fileData)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        urlRequest.httpBody = bodyData

        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    private func buildURLRequest<Response>(
        from request: APIRequest<Response>
    ) async throws -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = request.queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        // Inject additional headers
        if let headers = request.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Inject auth token
        if request.requiresAuth {
            guard let token = try await authTokenProvider?.currentToken() else {
                throw APIError.unauthorized
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode body
        if let body = request.body {
            do {
                urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encodingFailed(error)
            }
        }

        return urlRequest
    }

    private func performWithRetry<Response: Decodable>(
        urlRequest: URLRequest,
        retriesRemaining: Int
    ) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: urlRequest)
            try validateResponse(response, data: data)

            if Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        } catch let error as APIError {
            // Don't retry client errors (4xx) except rate-limiting
            switch error {
            case .rateLimited(let seconds):
                if retriesRemaining > 0 {
                    let delay = UInt64((seconds ?? 1) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    return try await performWithRetry(urlRequest: urlRequest, retriesRemaining: retriesRemaining - 1)
                }
                throw error
            case .httpError(let code, _) where code >= 500:
                if retriesRemaining > 0 {
                    // Exponential backoff: 1s, 2s, 4s
                    let attempt = configuration.maxRetries - retriesRemaining
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                    return try await performWithRetry(urlRequest: urlRequest, retriesRemaining: retriesRemaining - 1)
                }
                throw error
            default:
                throw error
            }
        } catch {
            if retriesRemaining > 0 {
                let attempt = configuration.maxRetries - retriesRemaining
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                return try await performWithRetry(urlRequest: urlRequest, retriesRemaining: retriesRemaining - 1)
            }
            throw APIError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw APIError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
            throw APIError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            // Attempt to decode server error message
            if let errorBody = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw APIError.serverError(message: errorBody.message)
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: data)
        }
    }
}

// MARK: - Supporting Types

/// Placeholder type for requests that return no body.
public struct EmptyResponse: Codable, Sendable {
    public init() {}
}

/// Server error response format.
private struct ServerErrorResponse: Codable {
    let message: String
    let code: String?
}

/// Type-erased Encodable wrapper for encoding heterogeneous body types.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
