import Foundation

/// Animated processing indicator with elapsed time display
/// Shows "✻ Processing for X.Xs" while waiting for LLM response
struct ProcessingIndicator {
    private(set) var isActive: Bool
    private(set) var startTime: Date?
    var message: String
    
    /// Spinner animation frames
    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var frameIndex: Int = 0
    
    init(message: String = "Processing") {
        self.isActive = false
        self.startTime = nil
        self.message = message
    }
    
    /// Start the processing indicator
    mutating func start() {
        isActive = true
        startTime = Date()
        frameIndex = 0
    }
    
    /// Stop the processing indicator
    mutating func stop() {
        isActive = false
        startTime = nil
    }
    
    /// Get elapsed time since start
    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    /// Format elapsed time as "X.Xs"
    var formattedElapsedTime: String {
        String(format: "%.1fs", elapsedTime)
    }
    
    /// Advance to next animation frame
    mutating func nextFrame() {
        frameIndex = (frameIndex + 1) % Self.spinnerFrames.count
    }
    
    /// Current spinner character
    var currentSpinner: String {
        Self.spinnerFrames[frameIndex]
    }
    
    /// Render the processing indicator
    /// Returns "✻ Processing for 2.3s" format
    func render() -> String {
        guard isActive else { return "" }
        return "  \(currentSpinner) \(message) for \(formattedElapsedTime)"
    }
    
    /// Render with custom spinner (for animation)
    func render(spinner: String) -> String {
        guard isActive else { return "" }
        return "  \(spinner) \(message) for \(formattedElapsedTime)"
    }
}
