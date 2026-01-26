import Foundation

/// Protocol for status bar management
protocol StatusBarManagerProtocol {
    var audioStatus: CaptureStatus { get set }
    var micStatus: CaptureStatus { get set }
    var currentChannel: AudioChannel { get set }
    var permissionStatus: PermissionStatus { get set }
    
    func render() -> String
}

/// Manages and renders the status bar at the bottom of the TUI
/// Displays audio/mic status, channel, and permissions
final class StatusBarManager: StatusBarManagerProtocol {
    var audioStatus: CaptureStatus
    var micStatus: CaptureStatus
    var currentChannel: AudioChannel
    var permissionStatus: PermissionStatus
    
    init(
        audioStatus: CaptureStatus = .inactive,
        micStatus: CaptureStatus = .inactive,
        currentChannel: AudioChannel = .speaker,
        permissionStatus: PermissionStatus = PermissionStatus()
    ) {
        self.audioStatus = audioStatus
        self.micStatus = micStatus
        self.currentChannel = currentChannel
        self.permissionStatus = permissionStatus
    }
    
    /// Render the status bar as a formatted string
    /// Format: 🎧 Headphone │ 🔊 Audio: ON │ 🎤 Mic: ON │ ✓ Permissions
    func render() -> String {
        let channelPart = "\(currentChannel.icon) \(currentChannel.label)"
        let audioPart = "🔊 Audio: \(audioStatus.display)"
        let micPart = "🎤 Mic: \(micStatus.display)"
        let permPart = permissionStatus.display
        
        return "  \(channelPart) │ \(audioPart) │ \(micPart) │ \(permPart)"
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
}
