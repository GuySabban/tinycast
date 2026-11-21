#!/bin/bash
# Times Look's recognition at three settings (README.md). Usage: run.sh [--runs N] [--png file]
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
# The shipped 2048 × 2048 pixel cap reads a 5K screen at 2731 px; this variant keeps 4096 px.
variant 's/maximumPixels = 2048 \* 2048/maximumPixels = 4096 * 2304/' FullExtractor.swift 'maximumPixels = 4096 \* 2304'
# Shipped cap in 768 px strips: macOS 27.2 read a 512 px strip fully and 2048 px ones badly.
variant 's/stripHeight = 2048/stripHeight = 768/; s/stripOverlap = 256/stripOverlap = 192/' \
    StripExtractor.swift 'stripHeight = 768'
# Rebuilt only when a source is newer, so a rerun times the same binaries' first call again.
build() {
    local out=$1; shift
    if [[ -x "$out" ]] && [[ -z "$(find "$@" -newer "$out" -print -quit)" ]]; then return; fi
    echo "building $(basename "$out")"
    xcrun swiftc -swift-version 6 -O "$@" -o "$out"
}
build "$OUT/AccurateHelper" "$S/ClipboardTextExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/FastHelper" "$OUT/FastExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/Accurate4096Helper" "$OUT/FullExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/Accurate768StripHelper" "$OUT/StripExtractor.swift" "$S/ClipboardTextHelper.swift"
build "$OUT/LookRecognitionBench" Tinycast/Features/Clipboard/Model/*.swift \
    Tinycast/Platform/Images/ImageDerivative.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
    "$S/ClipboardTextWorker.swift" Tinycast/Platform/ProcessExit.swift \
    Scripts/fork/look-recognition-bench/LookRecognitionBench.swift
sw_vers | tr '\n' ' '; sysctl -n machdep.cpu.brand_string
xcode-select -p
# One helper failing must not cost the others' timings.
for helper in AccurateHelper FastHelper Accurate4096Helper Accurate768StripHelper; do
    "$OUT/LookRecognitionBench" "$OUT/$helper" --dump "$OUT/$helper.txt" "$@" || echo "$helper: bench exited $?"
done
