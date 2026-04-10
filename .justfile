bench:
  moon bench

bench-accept:
  moon bench > .bench-baseline

test:
  node scripts/gen-tests.js
  node scripts/gen-gfm-tests.js
  moon test --target js -p mizchi/compat_tests

# Run VRT (geometry + screenshot) for the playground editor.
vrt:
  pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts

# Regenerate screenshot VRT baselines after an intentional UI change.
vrt-update:
  pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts --update-snapshots
