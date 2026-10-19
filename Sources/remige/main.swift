import Darwin
import RemigeCLIKit

let code = await RemigeCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code)
