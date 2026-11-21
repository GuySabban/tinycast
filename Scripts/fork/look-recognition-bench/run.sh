#!/bin/bash
# Time Look's recognition on a 5K test page at .accurate, .fast and .accurate at 4096 px. Usage: run.sh [--runs N] [--png file]
set -euo pipefail

cd "$(dirname "$0")/../../.." || exit 1
OUT=build/look-recognition-bench
S=Tinycast/Features/Clipboard/Service
mkdir -p "$OUT"
# A variant file is replaced only when its text changes, so it does not force a rebuild.
variant() {
    sed "$1" "$S/ClipboardTextExtractor.swift" > "$OUT/$2.new"
    grep -q "$3" "$OUT/$2.new"
    if cmp -s "$OUT/$2.new" "$OUT/$2"; then rm "$OUT/$2.new"; else mv "$OUT/$2.new" "$OUT/$2"; fi
}
variant 's/recognitionLevel = \.accurate/recognitionLevel = .fast/' FastExtractor.swift 'recognitionLevel = .fast'
# The shipped cap is 2048 × 2048 pixels, which scales a 5K screen to 2731 px; this variant keeps 4096 px.
variant 's/maximumPixels = 2048 \* 2048/maximumPixels = 4096 * 2304/' FullExtractor.swift 'maximumPixels = 4096 \* 2304'
# Rebuilt only when a source is newer, so a rerun times the same binaries' first call again.
build() {
    local out=$1; shift
    if [[ -x "$out" ]] && [[ -z "$(find "$@" -newer "$out" -print -quit)" ]]; then return; fi
    xcrun swiftc -swift-version 6 -O "$@" -o "$out"
}
build "$OUT/AccurateHelper" "$S/ClipboardTextExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/FastHelper" "$OUT/FastExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/Accurate4096Helper" "$OUT/FullExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/LookRecognitionBench" Tinycast/Features/Clipboard/Model/*.swift \
    Tinycast/Platform/Images/ImageDerivative.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
    "$S/ClipboardTextWorker.swift" Tinycast/Platform/ProcessExit.swift \
    Scripts/fork/look-recognition-bench/LookRecognitionBench.swift
sw_vers | tr '\n' ' '; sysctl -n machdep.cpu.brand_string
xcode-select -p
# One helper failing must not cost the others' timings.
for helper in AccurateHelper FastHelper Accurate4096Helper; do
    "$OUT/LookRecognitionBench" "$OUT/$helper" --dump "$OUT/$helper.txt" "$@" || echo "$helper: bench exited $?"
done
