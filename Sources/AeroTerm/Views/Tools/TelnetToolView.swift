import SwiftUI

public struct TelnetToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @State private var cmdInput: String = ""

    private var engine: TelnetEngine {
        if let eng = sessionManager.telnetEngines[session.id] {
            return eng
        }
        let eng = TelnetEngine()
        sessionManager.telnetEngines[session.id] = eng
        return eng
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Full Screen Stream Output
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(engine.terminalOutput.isEmpty ? "\(loc.text("telnet_connecting")) \(session.host):\(session.port)..." : engine.terminalOutput)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .id("bottom")
                    }
                    .onChange(of: engine.terminalOutput) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Bottom Input Line
                HStack(spacing: 8) {
                    Text(">")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)

                    TextField(loc.text("enter_telnet_cmd"), text: $cmdInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                        .onSubmit {
                            if !cmdInput.isEmpty {
                                engine.sendCommand(cmdInput)
                                cmdInput = ""
                            }
                        }
                }
                .padding(10)
                .background(Color.black.opacity(0.85))
            }
        }
        .onAppear {
            if !engine.isConnected && !engine.isConnecting {
                engine.connect(host: session.host, port: session.port)
            }
        }
    }
}
