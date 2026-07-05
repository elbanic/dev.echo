import Foundation

/// Shell command executor for setup wizard
/// Handles external command execution (ollama, curl, aws)
struct ShellExecutor {
    /// Run command and capture output
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Command arguments
    /// - Returns: Command output as string
    /// - Throws: ShellError on failure
    @discardableResult
    static func run(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.commandFailed(command: command, exitCode: process.terminationStatus, output: output)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run command and return exit code (does not throw)
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Command arguments
    /// - Returns: Exit code
    static func execute(_ command: String, arguments: [String] = []) -> Int32 {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    /// Run command interactively (shows output to user)
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Command arguments
    /// - Returns: Exit code
    static func executeInteractive(_ command: String, arguments: [String] = []) -> Int32 {
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    /// Check if command exists in PATH
    /// - Parameter command: Command name to check
    /// - Returns: true if command exists
    static func commandExists(_ command: String) -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Get the path of a command
    /// - Parameter command: Command name
    /// - Returns: Full path if found, nil otherwise
    static func commandPath(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
        return nil
    }
}

/// Shell execution errors
enum ShellError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case commandNotFound(command: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .commandNotFound(let command):
            return "Command '\(command)' not found"
        }
    }
}
