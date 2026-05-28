.PHONY: gen gen-l10n gen-watch format analyze test test-integration test-golden build-android-debug build-android-release-arm64 ci

gen-l10n:
	flutter gen-l10n

gen: gen-l10n
	dart run build_runner build --delete-conflicting-outputs

gen-watch:
	dart run build_runner watch --delete-conflicting-outputs

format:
	dart format .

analyze:
	bash scripts/check_reward_accent.sh
	dart analyze --fatal-infos
	bash scripts/check_hardcoded_colors.sh
	bash scripts/check_typography_call_sites.sh
	bash scripts/check_no_developer_log.sh

test:
	flutter test --exclude-tags integration --exclude-tags golden

# Golden image tests (post-session summary panel + future visual-gate
# pins). EXCLUDED from `make test` / CI because golden bytes vary across
# host platforms (text shaping) — run locally on the same host that baked
# the goldens. See `test/helpers/tolerant_golden_comparator.dart`.
test-golden:
	flutter test --tags golden

# Integration tests require a live local Supabase (`npx supabase start`).
# Excluded from `make test` and CI; run explicitly with `make test-integration`.
test-integration:
	flutter test --tags integration

build-android-debug:
	flutter build apk --debug --no-shrink

ci: format gen analyze test build-android-debug

build-android-release-arm64:
	flutter build apk --split-per-abi --target-platform android-arm64
