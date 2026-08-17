import SwiftUI

public struct TCPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    @State private var sendText: String = "Hello AeroTerm TCP!"
    @State private var isHexSend: Bool = false
    @State private var appendNewline: Bool = true

    private var clientEngine: TCPClientEngine {
        if let engine = sessionManager.tcpClientEngines[session.id] {
            return engine
        }
        let engine = TCPClientEngine()
        sessionManager.tcpClientEngines[session.id] = engine
        return engine
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.08, green: 0.09, blue: 0.11)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Full Screen Stream Log Area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if clientEngine.logs.isEmpty {
                                VStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white.opacity(0.2))
                                    Text(loc.text("tcp_ready_waiting"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.5))
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 260)
                            } else {
                                ForEach(clientEngine.logs) { item in
                                    logRow(item: item)
                                        .id(item.id)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: clientEngine.logs.count) {
                        if let last = clientEngine.logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Bottom Compact Send Bar
                HStack(spacing: 8) {
                    Toggle(loc.text("hex_mode"), isOn: $isHexSend)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))

                    TextField(isHexSend ? "Hex payload (e.g. 48 65 6C 6C 6F)..." : loc.text("enter_tcp_payload"), text: $sendText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(5)
                        .onSubmit {
                            performSend()
                        }

                    Button(loc.text("send_btn")) {
                        performSend()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
            }

            // Floating Minimal Status Capsule
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(clientEngine.isConnected ? Color.green : Color.yellow)
                            .frame(width: 5, height: 5)
                        Text("\(session.host):\(session.port)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)
                    .padding(8)
                }
                Spacer()
            }
        }
        .onAppear {
            if !clientEngine.isConnected && !clientEngine.isConnecting {
                clientEngine.connect(host: session.host, port: session.port)
            }
        }
    }

    private func logRow(item: NetworkLogItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(item.direction.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(item.direction.color)
                .cornerRadius(2)

            Text(item.timestamp, style: .time)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(item.direction == .send ? Color.cyan : (item.direction == .receive ? Color.green : Color.white.opacity(0.8)))
                    .textSelection(.enabled)

                if let hex = item.hexRepresentation, !hex.isEmpty {
                    Text("HEX: \(hex)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
        }
    }

    private func performSend() {
        guard !sendText.isEmpty else { return }
        if isHexSend {
            clientEngine.sendHex(sendText)
        } else {
            clientEngine.sendText(sendText, addNewline: appendNewline)
        }
    }
}
