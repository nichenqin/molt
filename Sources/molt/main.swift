import Darwin
import MoltCLIKit

let code = await MoltCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code)
