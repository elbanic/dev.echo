import Foundation

/// Progress display utilities for setup wizard
struct SetupProgress {
    // MARK: - Status Indicators

    /// Show success message with checkmark
    static func showSuccess(_ message: String) {
        print("  \u{001B}[32m✓\u{001B}[0m \(message)")
    }

    /// Show failure message with X
    static func showFailure(_ message: String) {
        print("  \u{001B}[31m✗\u{001B}[0m \(message)")
    }

    /// Show skipped message with circle
    static func showSkipped(_ message: String) {
        print("  \u{001B}[33m○\u{001B}[0m \(message)")
    }

    /// Show info message
    static func showInfo(_ message: String) {
        print("  \u{001B}[36mℹ\u{001B}[0m \(message)")
    }

    /// Show warning message
    static func showWarning(_ message: String) {
        print("  \u{001B}[33m⚠\u{001B}[0m \(message)")
    }

    // MARK: - Step Progress

    /// Show step header with number
    static func showStep(_ step: Int, total: Int, name: String) {
        print("\n\u{001B}[1m[\(step)/\(total)] \(name)\u{001B}[0m")
    }

    /// Show section header
    static func showSection(_ title: String) {
        print("\n\u{001B}[1m\(title)\u{001B}[0m")
    }

    // MARK: - Spinner

    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    /// Run action with spinner
    /// - Parameters:
    ///   - message: Message to show while running
    ///   - action: The async action to perform
    /// - Returns: Action result
    static func withSpinner<T>(_ message: String, action: @escaping () throws -> T) rethrows -> T {
        var frameIndex = 0
        var isRunning = true

        // Start spinner in background
        let spinnerThread = Thread {
            while isRunning {
                print("\r  \(spinnerFrames[frameIndex]) \(message)...", terminator: "")
                fflush(stdout)
                frameIndex = (frameIndex + 1) % spinnerFrames.count
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        spinnerThread.start()

        defer {
            isRunning = false
            spinnerThread.cancel()
            print("\r\u{001B}[K", terminator: "") // Clear spinner line
            fflush(stdout)
        }

        return try action()
    }

    /// Show progress message (no spinner, just animated dots)
    static func showProgress(_ message: String) {
        print("  \u{001B}[36m⏳\u{001B}[0m \(message)...")
    }

    /// Clear the current line
    static func clearLine() {
        print("\r\u{001B}[K", terminator: "")
        fflush(stdout)
    }

    // MARK: - Summary

    /// Print a summary separator line
    static func printSeparator() {
        print("\n" + String(repeating: "━", count: 40))
    }

    /// Print a light separator line
    static func printLightSeparator() {
        print(String(repeating: "─", count: 40))
    }
}
