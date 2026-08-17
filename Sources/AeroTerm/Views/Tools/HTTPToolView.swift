import SwiftUI

public struct HTTPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    @State private var method: String = "GET"
    @State private var urlInput: String = ""
    @State private var requestBody: String = "{\n  \"message\": \"Hello from AeroTerm\"\n}"
    @State private var selectedTab: Int = 0 // 0: Body, 1: Headers

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    @StateObject private var engine = HTTPEngine()

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部请求栏 (Method + URL + Send)
            HStack(spacing: 8) {
                Picker("", selection: $method) {
                    ForEach(methods, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .frame(width: 100)
                .pickerStyle(.menu)

                TextField("http://127.0.0.1:8080/api/v1/health", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(7)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .onSubmit {
                        executeRequest()
                    }

                Button {
                    executeRequest()
                } label: {
                    HStack(spacing: 5) {
                        if engine.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(engine.isLoading || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))

            Divider().background(Color.white.opacity(0.1))

            // 主体分栏：上方/左侧请求参数，下方/右侧响应视图
            HSplitView {
                // 左侧/上方：Request 编辑器
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Request Payload")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.3))

                    TextEditor(text: $requestBody)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(6)
                        .scrollContentBackground(.hidden)
                        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
                }
                .frame(minWidth: 260)

                // 右侧/下方：Response 展示区
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Response")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Spacer()

                        if let resp = engine.lastResponse {
                            HStack(spacing: 8) {
                                Text("\(resp.statusCode) \(resp.isSuccess ? "OK" : "ERR")")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(resp.isSuccess ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                    .foregroundColor(resp.isSuccess ? .green : .red)
                                    .cornerRadius(4)

                                Text(String(format: "%.1f ms", resp.durationMs))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text("\(resp.byteCount) B")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.3))

                    if let err = engine.errorMessage {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
                    } else if let resp = engine.lastResponse {
                        ScrollView {
                            Text(resp.bodyText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(red: 0.85, green: 0.90, blue: 0.95))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .textSelection(.enabled)
                        }
                        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
                    } else {
                        VStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "globe.badge.chevron.backward")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.2))
                            Text("Ready to test HTTP endpoint. Click Send above.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
                    }
                }
                .frame(minWidth: 320)
            }
        }
        .onAppear {
            if urlInput.isEmpty {
                urlInput = "http://\(session.host):\(session.port)/"
            }
        }
    }

    private func executeRequest() {
        engine.sendRequest(
            method: method,
            urlString: urlInput,
            headers: ["Content-Type": "application/json"],
            body: method == "GET" || method == "HEAD" ? nil : requestBody
        )
    }
}
