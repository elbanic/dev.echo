import Foundation

/// Audio/microphone capture status
enum CaptureStatus: Equatable {
    case active    // ON (green indicator)
    case inactive  // OFF (gray indicator)
    
    var display: String {
        switch self {
        case .active: return "ON"
        case .inactive: return "OFF"
        }
    }
}

/// Current audio output channel
enum AudioChannel: Equatable {
    case headphone  // 🎧 Headphone output
    case speaker    // 🔈 Speaker output
    
    var icon: String {
        switch self {
        case .headphone: return "🎧"
        case .speaker: return "🔈"
        }
    }
    
    var label: String {
        switch self {
        case .headphone: return "Headphone"
        case .speaker: return "Speaker"
        }
    }
}

/// Permission status for screen capture and microphone
struct PermissionStatus: Equatable {
    var screenCapture: Bool
    var microphone: Bool
    
    init(screenCapture: Bool = false, microphone: Bool = false) {
        self.screenCapture = screenCapture
        self.microphone = microphone
    }
    
    var allGranted: Bool {
        screenCapture && microphone
    }
    
    var display: String {
        if allGranted {
            return "✓ Permissions"
        } else {
            var missing: [String] = []
            if !screenCapture { missing.append("Screen") }
            if !microphone { missing.append("Mic") }
            return "✗ \(missing.joined(separator: ", "))"
        }
    }
}
