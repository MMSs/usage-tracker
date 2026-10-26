import Foundation
import ReleaseTools

/// Command line front end for the release workflows.
func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// Reads `--name value` pairs after the subcommand.
func options(_ arguments: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let name = arguments[index]
        guard name.hasPrefix("--"), index + 1 < arguments.count else { fail("bad arguments near \(name)") }
        result[String(name.dropFirst(2))] = arguments[index + 1]
        index += 2
    }
    return result
}

func required(_ options: [String: String], _ name: String) -> String {
    guard let value = options[name] else { fail("missing --\(name)") }
    return value
}

func readFile(_ path: String) -> String {
    guard let handle = FileHandle(forReadingAtPath: path), let data = try? handle.readToEnd() ?? Data() else { fail("cannot read \(path)") }
    return String(decoding: data, as: UTF8.self)
}

func writeFile(_ text: String, to path: String) {
    do { try text.write(toFile: path, atomically: true, encoding: .utf8) } catch { fail("cannot write \(path)") }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "check-title":
    guard arguments.count == 2 else { fail("usage: release-tool check-title <title>") }
    if ConventionalTitle(arguments[1]) == nil {
        print("PR title must start with a type, e.g. \"fix: …\". Allowed: feat, fix, perf, docs, ci, chore, refactor, test, build.")
        exit(1)
    }

case "plan":
    let opts = options(Array(arguments.dropFirst()))
    let previous = required(opts, "previous-tag")
    let repository = required(opts, "repository")
    let summary = readFile(required(opts, "first-release-summary"))
    let notesMD = required(opts, "notes-md")
    let notesHTML = required(opts, "notes-html")
    let log = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)

    let commits = ReleaseCommit.parseLog(log)
    let plan: ReleasePlan?
    do {
        plan = try ReleasePlanner.plan(commits: commits, previousTag: previous.isEmpty ? nil : previous)
    } catch {
        fail("\(error)")
    }
    for subject in ReleasePlanner.ignoredSubjects(in: commits) {
        FileHandle.standardError.write(Data("skipped: \(subject)\n".utf8))
    }
    guard let plan else {
        print("version=")
        exit(0)
    }
    writeFile(ReleaseNotesRenderer.markdown(plan, repository: repository, firstReleaseSummary: summary), to: notesMD)
    writeFile(ReleaseNotesRenderer.html(plan, repository: repository, firstReleaseSummary: summary), to: notesHTML)
    print("version=\(plan.version)")

case "appcast":
    let opts = options(Array(arguments.dropFirst()))
    guard
        let version = SemanticVersion(tag: "v" + required(opts, "version")),
        let url = URL(string: required(opts, "url")),
        let length = Int(required(opts, "length"))
    else { fail("invalid --version, --url or --length") }
    print(Appcast.xml(
        version: version, url: url, length: length, edSignature: required(opts, "signature"),
        notesHTML: readFile(required(opts, "notes-html")), published: Date(), minimumSystemVersion: "26.0"
    ), terminator: "")

default:
    fail("usage: release-tool check-title|plan|appcast")
}
