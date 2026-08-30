bench:
    moon bench

# Reproduce the @mizchi/markdown rows in ox-content's competitor benchmark.
bench-competitor runs="7":
    pnpm run build:moon
    pnpm run build:wasm
    node scripts/benchmark-competitor.mjs --runs={{ runs }}

# Build the Wasm GC + JS String Builtins npm subpath.
wasm-build:
    pnpm run build:wasm

# Run the wasm scanner and parse workloads that exercise SIMD fast paths.
bench-simd:
    moon bench --target wasm -p mizchi/markdown -f bench_scanner.mbt
    moon bench --target wasm -p mizchi/markdown -f bench.mbt -i 0-4
    moon bench --target wasm -p mizchi/markdown -f bench.mbt -i 4
    moon bench --target wasm -p mizchi/markdown -f bench_html.mbt -i 0-2
    moon bench --target wasm -p mizchi/markdown -f bench_html.mbt -i 2
    moon bench --target wasm -p mizchi/markdown -f bench_html.mbt -i 3

# Record a native Time Profiler trace for the 1 MiB benchmark corpus.
profile-native mode="parse" iterations="100":
    moon run --profile --release --target native src/cmd/profile -- "{{ mode }}" "{{ iterations }}"

# Record a V8 CPU profile for the same 1 MiB workload on the JS backend.
profile-js mode="parse" iterations="50":
    mkdir -p _build/js/release/profile/cmd/profile
    NODE_OPTIONS="--cpu-prof --cpu-prof-dir=_build/js/release/profile/cmd/profile" moon run --release --target js src/cmd/profile -- "{{ mode }}" "{{ iterations }}"

# Rebuild the synchronous inline Wasm SIMD kernel used by the JS backend.
inline-wasm-build:
    node scripts/embed-inline-marker-wasm.mjs

# Verify that the embedded Wasm bytes match their WAT source.
inline-wasm-check:
    node scripts/embed-inline-marker-wasm.mjs --check

bench-accept:
    moon bench > .bench-baseline

test:
    node scripts/gen-spec-tests.js
    node scripts/gen-tests.js
    node scripts/gen-gfm-tests.js
    moon test --target js src
    moon test --target wasm src
    moon test --target wasm-gc src
    moon test --target js src/spec_tests
    moon test --target js src/cmark_tests
    moon test --target js src/gfm_tests
    moon test --target js src/gfm_html_tests
    moon test --target wasm src/gfm_html_tests
    moon test --target js src/html_tests
    moon test --target native src/mmmd_native_core

# Run VRT (geometry + screenshot) for the playground editor.
vrt:
    pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts

# Regenerate screenshot VRT baselines after an intentional UI change.
vrt-update:
    pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts --update-snapshots

playground-build:
    moon build --target js --release
    pnpm vite build

# Build the native CLI. Install or rename the resulting binary as `mmmd`.
build-native:
    moon build --target native --release src/cmd/mmmd-native

playground-deploy:
    just playground-build
    pnpm exec wrangler deploy
