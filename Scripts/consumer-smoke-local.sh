#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version|tag> [repo-url]"
  echo "Example: $0 1.0.14"
  echo "Example: $0 v1.0.14 https://github.com/midi2kit/MIDI2Kit-SDK.git"
  exit 1
fi

VERSION="$1"
if [[ "${VERSION}" == v* ]]; then
  VERSION="${VERSION#v}"
fi

REPO_URL="${2:-https://github.com/midi2kit/MIDI2Kit-SDK.git}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Running consumer smoke test"
echo "  version : ${VERSION}"
echo "  repo    : ${REPO_URL}"
echo "  workdir : ${WORKDIR}"

cat > "${WORKDIR}/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "midi2kit-sdk-consumer-smoke",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "${REPO_URL}", exact: "${VERSION}")
    ],
    targets: [
        .executableTarget(
            name: "midi2kit-sdk-consumer-smoke",
            dependencies: [
                .product(name: "MIDI2Kit", package: "MIDI2Kit-SDK")
            ]
        )
    ]
)
EOF

mkdir -p "${WORKDIR}/Sources/midi2kit-sdk-consumer-smoke"
cat > "${WORKDIR}/Sources/midi2kit-sdk-consumer-smoke/main.swift" <<'EOF'
import Foundation
import MIDI2Kit

@main
struct SmokeApp {
    static func main() throws {
        // Legacy currentValues shape
        let legacyCurrentValueJSON = """
        {
          "controlcc": 7,
          "value": 100,
          "name": "Volume",
          "displayValue": "100",
          "displayUnit": ""
        }
        """
        let value = try JSONDecoder().decode(PEXCurrentValue.self, from: Data(legacyCurrentValueJSON.utf8))
        guard value.controlCC == 7,
              value.value == .int(100),
              value.name == "Volume",
              value.displayValue == "100",
              value.displayUnit == "" else {
            fatalError("PEXCurrentValue decode failed: \(value)")
        }

        // KORG bankPC array shape
        let programDefJSON = """
        {
          "title": "Grand Piano",
          "bankPC": [0, 1, 48]
        }
        """
        let program = try JSONDecoder().decode(PEProgramDef.self, from: Data(programDefJSON.utf8))
        guard program.bankMSB == 0,
              program.bankLSB == 1,
              program.programNumber == 48,
              program.name == "Grand Piano" else {
            fatalError("PEProgramDef decode failed: \(program)")
        }

        // X-ProgramEdit with legacy fields
        let xProgramEditJSON = """
        {
          "name": "Legacy Program",
          "currentValues": [
            {
              "controlcc": 7,
              "value": 100,
              "name": "Volume",
              "displayValue": "100",
              "displayUnit": ""
            }
          ]
        }
        """
        let edit = try JSONDecoder().decode(PEXProgramEdit.self, from: Data(xProgramEditJSON.utf8))
        guard edit.currentValues?.first?.value == .int(100),
              edit.currentValues?.first?.displayValue == "100",
              edit.hasContent else {
            fatalError("PEXProgramEdit decode failed: \(edit)")
        }

        print("OK: MIDI2Kit-SDK consumer smoke passed")
    }
}
EOF

swift run --package-path "${WORKDIR}" -v

