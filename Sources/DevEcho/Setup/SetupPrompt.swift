import Foundation

/// Terminal prompts for setup wizard
struct SetupPrompt {
    /// Ask a yes/no question
    /// - Parameters:
    ///   - question: The question to ask
    ///   - defaultValue: Default answer if user just presses Enter
    /// - Returns: User's answer
    static func askYesNo(_ question: String, default defaultValue: Bool = true) -> Bool {
        let hint = defaultValue ? "[Y/n]" : "[y/N]"
        print("\(question) \(hint): ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return defaultValue
        }

        if input.isEmpty {
            return defaultValue
        }

        switch input.first {
        case "y":
            return true
        case "n":
            return false
        default:
            return defaultValue
        }
    }

    /// Ask for text input
    /// - Parameters:
    ///   - prompt: The prompt to show
    ///   - defaultValue: Default value if user just presses Enter
    /// - Returns: User's input or default
    static func askText(_ prompt: String, default defaultValue: String? = nil) -> String {
        if let defaultValue = defaultValue {
            print("\(prompt) [\(defaultValue)]: ", terminator: "")
        } else {
            print("\(prompt): ", terminator: "")
        }
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return defaultValue ?? ""
        }

        if input.isEmpty {
            return defaultValue ?? ""
        }

        return input
    }

    /// Ask for selection from multiple options
    /// - Parameters:
    ///   - prompt: The prompt to show
    ///   - options: Array of option strings
    ///   - defaultIndex: Default selection index (0-based)
    /// - Returns: Selected option string
    static func askSelect(_ prompt: String, options: [String], defaultIndex: Int = 0) -> String {
        print(prompt)
        for (index, option) in options.enumerated() {
            let marker = index == defaultIndex ? "*" : " "
            print("  \(marker) \(index + 1). \(option)")
        }
        print("Enter selection [1-\(options.count), default=\(defaultIndex + 1)]: ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return options[defaultIndex]
        }

        if input.isEmpty {
            return options[defaultIndex]
        }

        if let selection = Int(input), selection >= 1, selection <= options.count {
            return options[selection - 1]
        }

        return options[defaultIndex]
    }

    /// Press any key to continue
    static func waitForKey(_ message: String = "Press Enter to continue...") {
        print(message, terminator: "")
        fflush(stdout)
        _ = readLine()
    }
}
