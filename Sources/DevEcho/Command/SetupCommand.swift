import ArgumentParser
import Foundation

/// Setup subcommand: Interactive setup wizard for first-time configuration
struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Interactive setup wizard for first-time configuration"
    )

    @Flag(name: .long, help: "Auto-accept all defaults without prompting")
    var `default` = false

    @Flag(name: .customLong("skip-cloud"), help: "Skip AWS cloud configuration")
    var skipCloud = false

    func run() throws {
        var wizard = SetupWizard(useDefault: `default`, skipCloud: skipCloud)
        wizard.run()
    }
}
