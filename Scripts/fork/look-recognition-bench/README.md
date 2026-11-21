# Look recognition bench (Phase L step 3)

Times `ClipboardTextWorker.extract(imageData:)`, the entry Look will use, from helper start to text:
PNG bytes go to `ClipboardTextHelper image-stdin` through a pipe, as in the app. It is not part of
the app target. Results are in `docs/planning/BASELINE.md`, "Phase L step 3". `LOOK.md` section 9
sets the target: 1 s median, measured on the owner's Mac.

## Run

From the repository root, in Terminal, with Xcode 27 selected (`xcode-select -p`):

```sh
./Scripts/fork/look-recognition-bench/run.sh                  # 5K test page, 10 runs per helper
./Scripts/fork/look-recognition-bench/run.sh --png shot.png   # any PNG instead of the test page
./Scripts/fork/look-recognition-bench/run.sh --runs 20
```

It builds three helpers into the ignored `build/look-recognition-bench/` and runs each in turn. A
helper is rebuilt only when one of its sources is newer than it, so a second run times the same
binaries' first call again.

| Helper | Is |
| --- | --- |
| `AccurateHelper` | The shipped extractor: `.accurate`, pixel cap 2048 × 2048, so a 5K page is read at 2731 × 1536 |
| `FastHelper` | The same at `.fast` (D39) |
| `Accurate4096Helper` | `.accurate` with the cap raised to 4096 × 2304, the size `LOOK.md` row 5 assumed |

The test page is 5120 × 2880, a 5K display at scale 2: two columns of 140 lines of 11 pt body text,
plus one marker each at 9, 11 and 13 pt on rows of their own above the text and an 11 pt Hebrew
line below it (`LOOK.md` section 12, row 5). Each run prints the macOS build, chip and selected
Xcode, the languages Vision recognizes at each level, and per helper: the thermal state before and
after, the first (cold) run on its own, every timed run in order, the median, 95th percentile,
minimum and maximum, the line count of every run, and in how many runs each marker came back. A
failed run is listed and skipped, and a failed helper does not stop the next one, so the output
always has timings for whatever succeeded. Each call has a 180 s deadline. The last run's text is
kept as `build/look-recognition-bench/<helper>.txt`.
