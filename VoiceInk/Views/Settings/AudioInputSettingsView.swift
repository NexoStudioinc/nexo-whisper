import SwiftUI

struct AudioInputSettingsView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                heroSection
                inputModeSection

                switch audioDeviceManager.inputMode {
                case .systemDefault:
                    systemDefaultSection
                case .custom:
                    customDeviceSection
                case .prioritized:
                    prioritizedDevicesSection
                }
            }
            .nexoPage()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var heroSection: some View {
        NexoHero(
            title: "Audio Input",
            subtitle: "Choose which microphone Nexo Whisper uses to record your voice.",
            systemImage: "waveform"
        )
    }

    private var inputModeSection: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Input Mode", systemImage: "slider.horizontal.3",
                                  subtitle: "Pick how Nexo Whisper decides which input device to use.")
                Divider()
                HStack(spacing: NexoSpacing.lg) {
                    ForEach(AudioInputMode.allCases, id: \.self) { mode in
                        InputModeCard(
                            mode: mode,
                            isSelected: audioDeviceManager.inputMode == mode,
                            action: { audioDeviceManager.selectInputMode(mode) }
                        )
                    }
                }
            }
        }
    }

    private var systemDefaultSection: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Current Device", systemImage: "display",
                                  subtitle: "The input device your Mac is currently using by default.")
                Divider()
                HStack {
                    Image(systemName: "display")
                        .foregroundStyle(.secondary)

                    Text(audioDeviceManager.getSystemDefaultDeviceName() ?? "No device available")
                        .foregroundStyle(.primary)

                    Spacer()

                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                }
            }
        }
    }

    private var customDeviceSection: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader(title: "Available Devices", systemImage: "mic",
                                  subtitle: "Select the specific microphone you want to use.") {
                    Button(action: { audioDeviceManager.loadAvailableDevices() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Divider()
                VStack(spacing: NexoSpacing.md) {
                    ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                        DeviceSelectionCard(
                            name: device.name,
                            isSelected: audioDeviceManager.selectedDeviceID == device.id,
                            isActive: audioDeviceManager.getCurrentDevice() == device.id
                        ) {
                            audioDeviceManager.selectDevice(id: device.id)
                        }
                    }
                }
            }
        }
    }

    private var prioritizedDevicesSection: some View {
        Group {
            if audioDeviceManager.availableDevices.isEmpty {
                NexoCard { emptyDevicesState }
            } else {
                prioritizedDevicesContent
                availableDevicesContent
            }
        }
    }

    private var prioritizedDevicesContent: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Prioritized Devices", systemImage: "list.number",
                                  subtitle: "Devices are used in order of priority. If a device is unavailable, the next one is tried; if none are available, the built-in microphone is used.")
                Divider()

                if audioDeviceManager.prioritizedDevices.isEmpty {
                    Text("No prioritized devices")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    prioritizedDevicesList
                }
            }
        }
    }

    private var availableDevicesContent: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Available Devices", systemImage: "mic",
                                  subtitle: "Add a device to the priority list.")
                Divider()
                availableDevicesList
            }
        }
    }
    
    private var emptyDevicesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No Audio Devices")
                    .font(.headline)
                Text("Connect an audio input device to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(CardBackground(isSelected: false))
    }
    
    private var prioritizedDevicesList: some View {
        VStack(spacing: 12) {
            ForEach(audioDeviceManager.prioritizedDevices.sorted(by: { $0.priority < $1.priority })) { device in
                devicePriorityCard(for: device)
            }
        }
    }
    
    private func devicePriorityCard(for prioritizedDevice: PrioritizedDevice) -> some View {
        let device = audioDeviceManager.availableDevices.first(where: { $0.uid == prioritizedDevice.id })
        return DevicePriorityCard(
            name: prioritizedDevice.name,
            priority: prioritizedDevice.priority,
            isActive: device.map { audioDeviceManager.getCurrentDevice() == $0.id } ?? false,
            isPrioritized: true,
            isAvailable: device != nil,
            canMoveUp: prioritizedDevice.priority > 0,
            canMoveDown: prioritizedDevice.priority < audioDeviceManager.prioritizedDevices.count - 1,
            onTogglePriority: { audioDeviceManager.removePrioritizedDevice(id: prioritizedDevice.id) },
            onMoveUp: { moveDeviceUp(prioritizedDevice) },
            onMoveDown: { moveDeviceDown(prioritizedDevice) }
        )
    }
    
    private var availableDevicesList: some View {
        let unprioritizedDevices = audioDeviceManager.availableDevices.filter { device in
            !audioDeviceManager.prioritizedDevices.contains { $0.id == device.uid }
        }
        
        return Group {
            if unprioritizedDevices.isEmpty {
                Text("No additional devices available")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(unprioritizedDevices, id: \.id) { device in
                    DevicePriorityCard(
                        name: device.name,
                        priority: nil,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id,
                        isPrioritized: false,
                        isAvailable: true,
                        canMoveUp: false,
                        canMoveDown: false,
                        onTogglePriority: { audioDeviceManager.addPrioritizedDevice(uid: device.uid, name: device.name) },
                        onMoveUp: {},
                        onMoveDown: {}
                    )
                }
            }
        }
    }
    
    private func moveDeviceUp(_ device: PrioritizedDevice) {
        guard device.priority > 0,
              let currentIndex = audioDeviceManager.prioritizedDevices.firstIndex(where: { $0.id == device.id })
        else { return }
        
        var devices = audioDeviceManager.prioritizedDevices
        devices.swapAt(currentIndex, currentIndex - 1)
        updatePriorities(devices)
    }
    
    private func moveDeviceDown(_ device: PrioritizedDevice) {
        guard device.priority < audioDeviceManager.prioritizedDevices.count - 1,
              let currentIndex = audioDeviceManager.prioritizedDevices.firstIndex(where: { $0.id == device.id })
        else { return }
        
        var devices = audioDeviceManager.prioritizedDevices
        devices.swapAt(currentIndex, currentIndex + 1)
        updatePriorities(devices)
    }
    
    private func updatePriorities(_ devices: [PrioritizedDevice]) {
        let updatedDevices = devices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index)
        }
        audioDeviceManager.updatePriorities(devices: updatedDevices)
    }
}

struct InputModeCard: View {
    let mode: AudioInputMode
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch mode {
        case .systemDefault: return "display"
        case .custom: return "mic.circle.fill"
        case .prioritized: return "list.number"
        }
    }

    // LocalizedStringKey en vez de String para que SwiftUI auto-localice
    // los literales contra Localizable.xcstrings. Si fueran String, los
    // pasaríamos como variables y SwiftUI usaría la versión literal en EN.
    private var titleKey: LocalizedStringKey {
        switch mode {
        case .systemDefault: return "System Default"
        case .custom: return "Custom Device"
        case .prioritized: return "Prioritized"
        }
    }

    private var descriptionKey: LocalizedStringKey {
        switch mode {
        case .systemDefault: return "Use your Mac's default input"
        case .custom: return "Select a specific input device"
        case .prioritized: return "Set up device priority order"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleKey)
                        .font(.headline)

                    Text(descriptionKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

struct DeviceSelectionCard: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 18))
                
                Text(name)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                }
            }
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

struct DevicePriorityCard: View {
    let name: String
    let priority: Int?
    let isActive: Bool
    let isPrioritized: Bool
    let isAvailable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onTogglePriority: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    
    var body: some View {
        HStack {
            // Priority number or dash
            if let priority = priority {
                Text("\(priority + 1)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            } else {
                Text("-")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            
            // Device name
            Text(name)
                .foregroundStyle(isAvailable ? .primary : .secondary)
            
            Spacer()
            
            // Status and Controls
            HStack(spacing: 12) {
                // Active status
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                } else if !isAvailable && isPrioritized {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.windowBackgroundColor).opacity(0.4))
                        )
                }
                
                // Priority controls (only show if prioritized)
                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(canMoveUp ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)
                        
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(canMoveDown ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                    }
                }
                
                // Toggle priority button
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? .red : .blue)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(CardBackground(isSelected: false))
    }
} 
