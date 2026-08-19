import SwiftUI

public struct SerialSettingsForm: View {
    @Binding var devicePath: String
    @Binding var baudRate: Int
    @Binding var settings: SerialSettings
    var availablePorts: [SerialPortInfo]
    var onRefresh: () -> Void
    var showsMode: Bool = true

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var baudText = ""
    @State private var manualPath = false

    public init(
        devicePath: Binding<String>,
        baudRate: Binding<Int>,
        settings: Binding<SerialSettings>,
        availablePorts: [SerialPortInfo],
        onRefresh: @escaping () -> Void,
        showsMode: Bool = true
    ) {
        _devicePath = devicePath
        _baudRate = baudRate
        _settings = settings
        self.availablePorts = availablePorts
        self.onRefresh = onRefresh
        self.showsMode = showsMode
        let rate = baudRate.wrappedValue
        _baudText = State(initialValue: rate > 0 ? String(rate) : "115200")
        _manualPath = State(initialValue: availablePorts.isEmpty)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsMode {
                modePicker
            }

            deviceRow
            attributeGrid

            if settings.mode == .shell {
                shellExtras
            }
        }
        .onChange(of: baudRate) { _, value in
            let next = value > 0 ? String(value) : ""
            if baudText != next {
                baudText = next
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text("serial_mode_label"))
                .font(.system(size: 12, weight: .semibold))
            Picker("", selection: $settings.mode) {
                ForEach(SerialSessionMode.allCases) { mode in
                    Text(loc.text(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(settings.mode == .shell ? loc.text("serial_mode_shell_hint") : loc.text("serial_mode_tester_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deviceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loc.text("serial_port_label"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Label(loc.text("serial_refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                Toggle(loc.text("serial_manual_path"), isOn: $manualPath)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }

            if manualPath || availablePorts.isEmpty {
                TextField("/dev/cu.usbserial", text: $devicePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                if availablePorts.isEmpty {
                    Text(loc.text("no_serial_port_detected"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("", selection: $devicePath) {
                    ForEach(availablePorts, id: \.path) { port in
                        Text("\(port.name)  (\(port.path))").tag(port.path)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var attributeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                field(loc.text("baud_rate_label")) {
                    TextField(loc.text("serial_baud_placeholder"), text: $baudText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 120)
                        .onChange(of: baudText) { _, text in
                            if let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 {
                                baudRate = value
                            }
                        }
                }

                field(loc.text("serial_data_bits")) {
                    Picker("", selection: $settings.dataBits) {
                        ForEach(SerialDataBits.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                field(loc.text("serial_parity")) {
                    Picker("", selection: $settings.parity) {
                        ForEach(SerialParity.allCases) { item in
                            Text(loc.text(item.titleKey)).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                field(loc.text("serial_stop_bits")) {
                    Picker("", selection: $settings.stopBits) {
                        ForEach(SerialStopBits.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                field(loc.text("serial_flow_control")) {
                    Picker("", selection: $settings.flowControl) {
                        ForEach(SerialFlowControl.allCases) { item in
                            Text(loc.text(item.titleKey)).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                }

                Toggle(loc.text("serial_dtr"), isOn: $settings.dtr)
                    .toggleStyle(.checkbox)
                    .padding(.top, 22)
                Toggle(loc.text("serial_rts"), isOn: $settings.rts)
                    .toggleStyle(.checkbox)
                    .padding(.top, 22)
                Spacer()
            }
        }
    }

    private var shellExtras: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(loc.text("serial_shell_options"))
                .font(.system(size: 12, weight: .semibold))
            field(loc.text("serial_highlight_label")) {
                Picker("", selection: $settings.highlightStyle) {
                    ForEach(SerialHighlightStyle.allCases) { style in
                        Text(loc.text(style.titleKey)).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
            }
            Text(loc.text(settings.highlightStyle.hintKey))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            field(loc.text("serial_palette_label")) {
                TerminalPalettePicker(paletteID: $settings.colorSchemeID)
                    .frame(maxWidth: 240)
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
            content()
        }
    }
}
