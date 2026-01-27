import Foundation

/// Protocol for status bar management
protocol StatusBarManagerProtocol {
    var audioStatus: CaptureStatus { get set }
    var micStatus: CaptureStatus { get set }
    var currentChannel: AudioChannel { get set }
    var permissionStatus: PermissionStatus { get set }
    var kbStatus: KBConnectionStatus { get set }
    
    func render() -> String
}

/// KB connection status for Phase 2
/// Requirements: 11.3, 11.5
struct KBConnectionStatus {
    var isConnected: Bool
    var status: String  // "READY", "SYNCING", "FAILED", "UNKNOWN"
    var documentCount: Int
    var errorMessage: String?
    
    init(isConnected: Bool = false, status: String = "UNKNOWN", documentCount: Int = 0, errorMessage: String? = nil) {
        self.isConnected = isConnected
        self.status = status
        self.documentCount = documentCount
        self.errorMessage = errorMessage
    }
    
    var icon: String {
        if !isConnected {
            return "☁️"
        }
        switch status {
        case "READY": return "✅"
        case "SYNCING": return "🔄"
        case "FAILED": return "❌"
        default: return "❓"
        }
    }
    
    var display: String {
        if !isConnected {
            return "☁️ KB: --"
        }
        switch status {
        case "READY": return "☁️ KB: \(documentCount) docs"
        case "SYNCING": return "☁️ KB: syncing..."
        case "FAILED": return "☁️ KB: error"
        default: return "☁️ KB: --"
        }
    }
}

/// Manages and renders the status bar at the bottom of the TUI
/// Displays audio/mic status, channel, permissions, and KB status (Phase 2)
final class StatusBarManager: StatusBarManagerProtocol {
    var audioStatus: CaptureStatus
    var micStatus: CaptureStatus
    var currentChannel: AudioChannel
    var permissionStatus: PermissionStatus
    var kbStatus: KBConnectionStatus
    
    init(
        audioStatus: CaptureStatus = .inactive,
        micStatus: CaptureStatus = .inactive,
        currentChannel: AudioChannel = .speaker,
        permissionStatus: PermissionStatus = PermissionStatus(),
        kbStatus: KBConnectionStatus = KBConnectionStatus()
    ) {
        self.audioStatus = audioStatus
        self.micStatus = micStatus
        self.currentChannel = currentChannel
        self.permissionStatus = permissionStatus
        self.kbStatus = kbStatus
    }
    
    /// Render the status bar as a formatted string
    /// Format: 🎧 Headphone │ 🔊 Audio: ON │ 🎤 Mic: ON │ ☁️ KB: 5 docs │ ✓ Permissions
    func render() -> String {
        let channelPart = "\(currentChannel.icon) \(currentChannel.label)"
        let audioPart = "🔊 Audio: \(audioStatus.display)"
        let micPart = "🎤 Mic: \(micStatus.display)"
        let kbPart = kbStatus.display
        let permPart = permissionStatus.display
        
        return "  \(channelPart) │ \(audioPart) │ \(micPart) │ \(kbPart) │ \(permPart)"
    }
    
    /// Update audio capture status
    func setAudioStatus(_ status: CaptureStatus) {
        audioStatus = status
    }
    
    /// Update microphone capture status
    func setMicStatus(_ status: CaptureStatus) {
        micStatus = status
    }
    
    /// Update audio channel
    func setChannel(_ channel: AudioChannel) {
        currentChannel = channel
    }
    
    /// Update permission status
    func setPermissions(screenCapture: Bool? = nil, microphone: Bool? = nil) {
        if let sc = screenCapture {
            permissionStatus.screenCapture = sc
        }
        if let mic = microphone {
            permissionStatus.microphone = mic
        }
    }
    
    /// Update KB connection status (Phase 2)
    /// Requirements: 11.3, 11.5
    func setKBStatus(isConnected: Bool, status: String = "UNKNOWN", documentCount: Int = 0, errorMessage: String? = nil) {
        kbStatus = KBConnectionStatus(
            isConnected: isConnected,
            status: status,
            documentCount: documentCount,
            errorMessage: errorMessage
        )
    }
    
    /// Update KB status from KBSyncStatusMessage (Phase 2)
    func setKBStatus(from syncStatus: KBSyncStatusMessage) {
        kbStatus = KBConnectionStatus(
            isConnected: true,
            status: syncStatus.status,
            documentCount: syncStatus.documentCount,
            errorMessage: syncStatus.errorMessage
        )
    }
}
