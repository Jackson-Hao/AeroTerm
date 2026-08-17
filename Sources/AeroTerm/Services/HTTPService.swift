import Foundation
import Combine

public struct HTTPResponseData: Sendable {
    public let statusCode: Int
    public let durationMs: Double
    public let headers: [String: String]
    public let bodyText: String
    public let byteCount: Int
    public let isSuccess: Bool

    public init(
        statusCode: Int,
        durationMs: Double,
        headers: [String: String],
        bodyText: String,
        byteCount: Int,
        isSuccess: Bool
    ) {
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.headers = headers
        self.bodyText = bodyText
        self.byteCount = byteCount
        self.isSuccess = isSuccess
    }
}

@MainActor
public final class HTTPEngine: ObservableObject {
    @Published public var isLoading: Bool = false
    @Published public var lastResponse: HTTPResponseData? = nil
    @Published public var errorMessage: String? = nil

    private var currentTask: URLSessionDataTask?

    public init() {}

    public func sendRequest(
        method: String,
        urlString: String,
        headers: [String: String],
        body: String?
    ) {
        errorMessage = nil
        lastResponse = nil

        var finalURLStr = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalURLStr.lowercased().hasPrefix("http://") && !finalURLStr.lowercased().hasPrefix("https://") {
            finalURLStr = "http://" + finalURLStr
        }

        guard let url = URL(string: finalURLStr) else {
            self.errorMessage = "Invalid URL: \(urlString)"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15.0

        for (k, v) in headers where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        if let body = body, !body.isEmpty, (method == "POST" || method == "PUT" || method == "PATCH") {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }

        self.isLoading = true
        let startTime = CFAbsoluteTimeGetCurrent()

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let httpResp = response as? HTTPURLResponse else {
                    self.errorMessage = "Non-HTTP response received."
                    return
                }

                var headerDict: [String: String] = [:]
                for (k, v) in httpResp.allHeaderFields {
                    headerDict["\(k)"] = "\(v)"
                }

                let responseData = data ?? Data()
                let bodyString = String(data: responseData, encoding: .utf8) ?? String(data: responseData, encoding: .ascii) ?? "<Binary payload \(responseData.count) bytes>"

                self.lastResponse = HTTPResponseData(
                    statusCode: httpResp.statusCode,
                    durationMs: duration,
                    headers: headerDict,
                    bodyText: bodyString,
                    byteCount: responseData.count,
                    isSuccess: (200...299).contains(httpResp.statusCode)
                )
            }
        }

        self.currentTask = task
        task.resume()
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
}
