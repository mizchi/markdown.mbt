bench:
    moon bench

# Run the wasm scanner and parse workloads that exercise SIMD fast paths.
bench-simd:
    moon bench --target wasm -p mizchi/markdown -f bench_scanner.mbt
    moon bench --target wasm -p mizchi/markdown -f bench.mbt -i 0-4
    moon bench --target wasm -p mizchi/markdown -f bench.mbt -i 4
    moon bench --target wasm -p mizchi/markdown -f bench_html.mbt -i 0-2
    moon bench --target wasm -p mizchi/markdown -f bench_html.mbt -i 2
    moon bench --target wasm -p mizchi/markdown -f bench_html.mbt -i 3

bench-accept:
    moon bench > .bench-baseline

test:
    node scripts/gen-spec-tests.js
    node scripts/gen-tests.js
    node scripts/gen-gfm-tests.js
    moon test --target js src
    moon test --target wasm src
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
