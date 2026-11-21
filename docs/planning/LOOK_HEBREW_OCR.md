# On-device Hebrew text reading for Look — findings

## Recommendation
Tesseract 5 (`tessdata_best` heb+eng) as a second pass in the existing `ClipboardTextHelper`, run only when the capture has Hebrew (or always for an owner whose languages include Hebrew), with Vision kept for everything else. About 1 CPU second per screen, 19 MB of models, Apache-2.0, fully on the Mac, image stays in memory (libtesseract takes a pixel buffer; no file needed).
Open decision for the owner: AGENTS.md says "Zero third-party dependencies". Bundling libtesseract + leptonica (C/C++) breaks that; the alternative is to use a Tesseract the owner installs himself (Homebrew) and fall back to Vision-only when it is absent.

## Options

| Option | Hebrew? | Speed | Size | Licence | Privacy | Notes |
|---|---|---|---|---|---|---|
| Apple Vision `RecognizeTextRequest` | No (owner's 27.2, both levels) | fast | 0 | system | on-device | Latin digits/URLs may still be read inside Hebrew screens — owner check 1 |
| Apple Live Text / VisionKit `ImageAnalyzer` | Not listed on Apple's macOS feature-availability page | fast | 0 | system | on-device | Owner check 1 prints its list on 27.2 |
| Apple Foundation Models (`fm respond --image`) | Hebrew not an Apple Intelligence language; failed on owner's capture | slow | 0 | system | on-device | — |
| **Tesseract 5.5 best heb+eng** | Yes | ~1.0-1.4 s CPU/screen (VM) | 19.1 MB (heb 3.7 MB) | Apache-2.0 | on-device | CER 5.8-8.8%; dates, times, phones, codes exact; mixed Hebrew URL wrong |
| Tesseract 5.5 fast heb+eng | Yes | ~0.4-0.5 s | 5.1 MB (heb 0.96 MB) | Apache-2.0 | on-device | CER 9-30%; phone wrong 2/3, garbles mixed lines at 13-14 px |
| Community Paddle SVTRv2 Hebrew (`paddleocr-hebrew` 0.1.2, Rivok) | Yes | 9-11 s CPU | 182 MB | Apache-2.0 | on-device | Best CER (3.6-6.9%) but too slow/large; one-person models, ONNX Runtime needed |
| PaddleOCR PP-OCRv5 / RapidOCR official | No Hebrew recognizer | — | — | Apache-2.0 | — | read only |
| EasyOCR 1.7.2 | No (`he` not in its 86 languages) | — | — | Apache-2.0 | — | read wheel only |
| Surya 2.5 (690M VLM) | Hebrew not in its published table; Arabic 45% | ~40 s/page on M4 Max (their numbers) | ~1.4 GB | code Apache-2.0, weights OpenRAIL-M (paid above $5M revenue) | on-device | read only; too slow |
| Local VLM via MLX (Qwen-VL class) | Partial, unmeasured | many seconds | GBs | varies | on-device | not tried; same speed class as Surya |

## What I ran vs only read
**Ran** (Linux VM, 8 vCPU Xeon, one run each, synthetic 1600x900 screens with Hebrew+Latin lines at 16/13 px light and 14 px dark): Tesseract 5.5.2 fast and best, `paddleocr-hebrew` 0.1.2 via ONNX Runtime 1.23.2; checked RapidOCR 3.10.0's language enum and EasyOCR 1.7.2's wheel. All gave Hebrew in logical order. Target strings: `24.11.2026`, `14:30`, `054-1234567`, `https://example.co.il/דף`, `ABC-123`. Not a general ranking: tiny synthetic set, no Mac, no real screens.
**Read only**: Apple Vision/Live Text language support (apple.com/macos/feature-availability), Surya README (github.com/datalab-to/surya), PaddleOCR PP-OCRv5 multilingual list, tessdata file sizes (github.com/tesseract-ocr/tessdata_best, tessdata_fast).

Sources: https://github.com/tesseract-ocr/tesseract · https://github.com/tesseract-ocr/tessdata_best · https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/algorithm/PP-OCRv5/PP-OCRv5_multi_languages.en.md · https://huggingface.co/Rivok/paddleocr-hebrew · https://github.com/JaidedAI/EasyOCR · https://github.com/datalab-to/surya · https://www.apple.com/macos/feature-availability/

## Owner checks on the real Mac (not run by me; no Mac here)

**1. What Apple already reads, and whether Live Text lists Hebrew.** Open a Hebrew screen with a date, phone and link, then:
```sh
screencapture -x ~/Desktop/look-he.png
cat > ~/Desktop/he.swift <<'S'
import Foundation
import Vision
import VisionKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
print("VisionKit:", await ImageAnalyzer.supportedTextRecognitionLanguages)
var req = RecognizeTextRequest()
req.recognitionLevel = .accurate
print("Vision:", try req.supportedRecognitionLanguages)
let obs = try await req.perform(on: url)
for o in obs { print(o.topCandidates(1).first?.string ?? "") }
S
swift ~/Desktop/he.swift ~/Desktop/look-he.png
```
Report: whether `he` appears in either list, and whether the date, phone and link on that screen came out right even though the Hebrew words did not.

**2. Tesseract speed and quality on his screens.**
```sh
brew install tesseract
mkdir -p ~/tessdata
for l in heb eng; do curl -L -o ~/tessdata/$l.traineddata https://github.com/tesseract-ocr/tessdata_best/raw/main/$l.traineddata; done
time tesseract ~/Desktop/look-he.png stdout --tessdata-dir ~/tessdata -l heb+eng --oem 1 --psm 3
```
Report: the `real` time and whether the Hebrew lines, date, phone and link read right.

**3. Delete the test files**: `rm ~/Desktop/look-he.png ~/Desktop/he.swift` (the capture is on disk only for this test).

## Owner's run on his M3 (2026-11-21) and follow-up
- Vision and VisionKit on macOS 27.2 list 33 languages each, Hebrew not among them. Vision's `perform` then crashed in the `swift` interpreter (`e5rt_e5_compiler_compile call failed`, 11), so this script never showed what Vision reads on that screen.
- Tesseract best heb+eng, default page mode, on his 3420x2224 dark WhatsApp capture: 4.8 s total on the M3; it read the chat list in part and missed most of the message bubbles.
- On the VM, with his capture and his model files: **grayscale + invert + `--psm 11`** found 23/24 reference Hebrew lines (mean error 2.7% on the lines found) and 16/17 times/dates, vs 16/24 and 15/17 for his command. The preprocessing took 0.39 s. VM OCR 4.2 s vs 7.1 s for his command; the M3 should be proportionally faster. Output lines from the two panes come out interleaved, so the text can be searched and its dates and times detected, but it is not a clean transcript.
- Confirm on the Mac (optional):
```sh
brew install imagemagick
magick ~/Desktop/look-he.png -colorspace Gray -negate ~/Desktop/look-inv.png
time tesseract ~/Desktop/look-inv.png stdout --tessdata-dir ~/tessdata -l heb+eng --psm 11
rm ~/Desktop/look-he.png ~/Desktop/look-inv.png ~/Desktop/he.swift
```
