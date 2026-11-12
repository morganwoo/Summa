#!/usr/bin/env bash
# Runs the SummaCore Swift Testing suites on a Linux toolchain that predates
# Swift Testing (e.g. Swift 5.10) by rewriting the tests into a plain executable.
# On macOS use `swift test` or Xcode instead; this exists for CI boxes without Xcode.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
mkdir -p "$work/Sources/SummaCore" "$work/Sources/Runner"
cp "$here"/SummaCore/Sources/SummaCore/*.swift "$work/Sources/SummaCore/"
cat > "$work/Package.swift" <<'P'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Runner", targets: [
    .target(name: "SummaCore"),
    .executableTarget(name: "Runner", dependencies: ["SummaCore"]),
])
P
cat > "$work/Sources/Runner/Harness.swift" <<'P'
import Foundation
var failures = 0
var checks = 0
func expect(_ condition: @autoclosure () throws -> Bool, file: String = #fileID, line: Int = #line) {
    checks += 1
    let ok = (try? condition()) ?? false
    if !ok { failures += 1; print("  ✗ expectation failed at \(file):\(line)") }
}
func run(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do { try body() } catch { failures += 1; print("  ✗ threw \(error)") }
    print("\(failures == before ? "✓" : "✗") \(name)")
}
P
calls=""
for f in "$here"/SummaCore/Tests/SummaCoreTests/*.swift; do
  out="$work/Sources/Runner/$(basename "$f")"
  sed -e '/^import Testing$/d' -e 's/@testable import/import/' -e 's/#expect(/expect(/g' \
      -e 's/^@Suite //' -e 's/^    @Test func/    func/' "$f" > "$out"
  suite=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^struct\ ([A-Za-z0-9_]+) ]]; then suite="${BASH_REMATCH[1]}"; fi
    if [[ "$line" =~ ^\ \ \ \ func\ ([A-Za-z0-9_]+)\(\) ]]; then
      calls+="run(\"$suite.${BASH_REMATCH[1]}\") { try $suite().${BASH_REMATCH[1]}() }"$'\n'
    fi
  done < "$out"
done
{ echo "import Foundation"; echo "$calls"; echo 'print("\(checks) checks, \(failures) failures"); exit(failures == 0 ? 0 : 1)'; } > "$work/Sources/Runner/main.swift"
cd "$work" && swift build -c debug 2>&1 | grep -E "error|warning: unre|Compiling|Build" | tail -20 && swift run Runner
