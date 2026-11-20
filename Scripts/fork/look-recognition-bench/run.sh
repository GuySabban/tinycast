#!/bin/bash
# Time Look's recognition on a 5K test page at .accurate, .fast and .accurate at 4096 px. Usage: run.sh [--runs N] [--png file]
set -euo pipefail

cd "$(dirname "$0")/../../.." || exit 1
OUT=build/look-recognition-bench
S=Tinycast/Features/Clipboard/Service
mkdir -p "$OUT"
sed 's/recognitionLevel = \.accurate/recognitionLevel = .fast/' "$S/ClipboardTextExtractor.swift" > "$OUT/FastExtractor.swift"
grep -q 'recognitionLevel = .fast' "$OUT/FastExtractor.swift"
# The shipped cap is 2048 × 2048 pixels, which scales a 5K screen to 2731 px; this variant keeps 4096 px.
sed 's/maximumPixels = 2048 \* 2048/maximumPixels = 4096 * 2304/' "$S/ClipboardTextExtractor.swift" > "$OUT/FullExtractor.swift"
grep -q 'maximumPixels = 4096 \* 2304' "$OUT/FullExtractor.swift"
xcrun swiftc -swift-version 6 -O "$S/ClipboardTextExtractor.swift" "$S/ClipboardTextHelper.swift" \
    -o "$OUT/AccurateHelper"
xcrun swiftc -swift-version 6 -O "$OUT/FastExtractor.swift" "$S/ClipboardTextHelper.swift" -o "$OUT/FastHelper"
xcrun swiftc -swift-version 6 -O "$OUT/FullExtractor.swift" "$S/ClipboardTextHelper.swift" \
    -o "$OUT/Accurate4096Helper"
xcrun swiftc -swift-version 6 -O Tinycast/Features/Clipboard/Model/*.swift \
    Tinycast/Platform/Images/ImageDerivative.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
    "$S/ClipboardTextWorker.swift" Tinycast/Platform/ProcessExit.swift \
    Scripts/fork/look-recognition-bench/LookRecognitionBench.swift -o "$OUT/LookRecognitionBench"
sw_vers | tr '\n' ' '; sysctl -n machdep.cpu.brand_string
xcode-select -p
# One helper failing must not cost the others' timings.
for helper in AccurateHelper FastHelper Accurate4096Helper; do
    "$OUT/LookRecognitionBench" "$OUT/$helper" "$@" || echo "$helper: bench exited $?"
done
