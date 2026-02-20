import Foundation

@main
struct AsukuHookCLI {
    static func main() {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("Usage: asuku-hook <permission-request|notification>\n".utf8))
            exit(1)
        }

        let subcommand = args[1]

        // Read all stdin
        let inputData = FileHandle.standardInput.readDataToEndOfFile()

        do {
            switch subcommand {
            case "permission-request":
                try PermissionRequestHandler.handle(inputData: inputData)
            case "notification":
                try NotificationHandler.handle(inputData: inputData)
            default:
                FileHandle.standardError.write(
                    Data("Unknown subcommand: \(subcommand)\n".utf8))
                exit(1)
            }
        } catch {
            // Any error → exit 1 for fallback to normal terminal dialog
            FileHandle.standardError.write(
                Data("asuku-hook error: \(error)\n".utf8))
            exit(1)
        }
    }
}
