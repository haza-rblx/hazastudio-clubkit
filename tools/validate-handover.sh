#!/usr/bin/env bash
# validate-handover.sh
# Single-command validator for the quota-efficiency-pass-2026-06 handover state.
# Runs: stylua check, selene lint, rojo build, HttpApi counter-site count, wrapper migration count.
# Exits 0 if all green, 1 if any red.
#
# Usage:
#   ./tools/validate-handover.sh           # full check with colored output
#   ./tools/validate-handover.sh --quiet   # summary only (for CI)
#   ./tools/validate-handover.sh --json    # machine-readable output (for tooling)

set -uo pipefail

# -------- arg parsing --------
QUIET=0
JSON=0
for arg in "$@"; do
	case "$arg" in
	--quiet) QUIET=1 ;;
	--json) JSON=1 ;;
	-h | --help)
		echo "Usage: $0 [--quiet] [--json]"
		exit 0
		;;
	esac
done

# -------- output helpers --------
if [[ -t 1 ]] && [[ $JSON -eq 0 ]]; then
	GREEN='\033[0;32m'
	RED='\033[0;31m'
	YELLOW='\033[0;33m'
	BLUE='\033[0;34m'
	BOLD='\033[1m'
	NC='\033[0m'
else
	GREEN='' RED='' YELLOW='' BLUE='' BOLD='' NC=''
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
RESULTS=()

log_pass() {
	local name="$1"
	local detail="${2:-}"
	((PASS_COUNT++))
	RESULTS+=("PASS|$name|$detail")
	if [[ $QUIET -eq 0 ]] && [[ $JSON -eq 0 ]]; then
		echo -e "  ${GREEN}✓${NC} $name ${detail:+— $detail}"
	fi
}

log_fail() {
	local name="$1"
	local detail="${2:-}"
	((FAIL_COUNT++))
	RESULTS+=("FAIL|$name|$detail")
	if [[ $QUIET -eq 0 ]] && [[ $JSON -eq 0 ]]; then
		echo -e "  ${RED}✗${NC} $name ${detail:+— $detail}"
	fi
}

log_warn() {
	local name="$1"
	local detail="${2:-}"
	((WARN_COUNT++))
	RESULTS+=("WARN|$name|$detail")
	if [[ $QUIET -eq 0 ]] && [[ $JSON -eq 0 ]]; then
		echo -e "  ${YELLOW}⚠${NC} $name ${detail:+— $detail}"
	fi
}

section() {
	if [[ $QUIET -eq 0 ]] && [[ $JSON -eq 0 ]]; then
		echo ""
		echo -e "${BOLD}${BLUE}▶ $1${NC}"
	fi
}

# -------- pre-flight --------
section "Pre-flight"

# Verify we're in the project root
if [[ ! -f "default.project.json" ]]; then
	log_fail "project root" "default.project.json not found. Run from project root."
	echo -e "${RED}Fatal: not in project root${NC}" >&2
	exit 2
fi
log_pass "project root" "default.project.json found"

# Check tool availability
for tool in stylua selene rojo; do
	if command -v "$tool" >/dev/null 2>&1; then
		log_pass "tool: $tool" "$(command -v "$tool")"
	else
		log_fail "tool: $tool" "not found in PATH"
	fi
done

# -------- 1. stylua --------
section "1. Stylua formatting"

# Scope: src tree only (skip _non_rojo/, notes/, tools/donation-api/, etc. per .styluaignore)
STYLUA_TARGETS=(
	"src/ReplicatedStorage"
	"src/ServerScriptService"
	"src/StarterPlayer"
	"src/StarterPlayerScripts"
	"src"
	"tools"
)

STYLUA_FILES=""
for dir in "${STYLUA_TARGETS[@]}"; do
	[[ -d "$dir" ]] && STYLUA_FILES+="$dir "
done

if [[ -n "$STYLUA_FILES" ]]; then
	# --check exits 1 if any diffs, 0 if clean
	stylua_out=$(stylua --check $STYLUA_FILES 2>&1)
	stylua_rc=$?
	if [[ $stylua_rc -eq 0 ]]; then
		log_pass "stylua" "clean"
	elif [[ $stylua_rc -eq 1 ]]; then
		# Count diff lines (lines containing "Diff in")
		diff_count=$(echo "$stylua_out" | grep -c "Diff in" || true)
		log_warn "stylua" "$diff_count file(s) with formatting diffs (see HANDOVER.md note #6 — pre-existing in Main.server.luau, jangan mass-reformat)"
	else
		log_fail "stylua" "exit $stylua_rc: $stylua_out"
	fi
else
	log_warn "stylua" "no target files found"
fi

# -------- 2. selene --------
section "2. Selene linting"

# Scope: src tree + tools/ (Luau files only)
SELENE_TARGETS=(
	"src/ReplicatedStorage"
	"src/ServerScriptService"
	"src/StarterPlayer"
	"src/StarterPlayerScripts"
	"src"
	"tools"
)

SELENE_FILES=""
for dir in "${SELENE_TARGETS[@]}"; do
	[[ -d "$dir" ]] && SELENE_FILES+="$dir "
done

if [[ -n "$SELENE_FILES" ]]; then
	# selene exits 0 if no issues, 1 if issues (parse error / lint error)
	selene_out=$(selene $SELENE_FILES 2>&1)
	selene_rc=$?
	error_count=$(echo "$selene_out" | grep -cE "^error" || true)
	warning_count=$(echo "$selene_out" | grep -cE "^warning" || true)

	if [[ $selene_rc -eq 0 ]]; then
		log_pass "selene" "0 errors, 0 warnings"
	else
		if [[ $error_count -gt 0 ]]; then
			log_fail "selene" "$error_count error(s)"
		else
			# Warnings only — soft fail, count as warn
			log_warn "selene" "$warning_count warning(s), 0 errors (pre-existing, see HANDOVER note #6)"
		fi
	fi
else
	log_warn "selene" "no target files found"
fi

# -------- 3. rojo build --------
section "3. Rojo build"

BUILD_OUTPUT="/tmp/validate-handover-build-$$.rbxlx"
if rojo build default.project.json --output "$BUILD_OUTPUT" >/tmp/rojo-build.log 2>&1; then
	build_size=$(stat -c%s "$BUILD_OUTPUT" 2>/dev/null || stat -f%z "$BUILD_OUTPUT" 2>/dev/null)
	build_size_mb=$(awk "BEGIN {printf \"%.2f\", $build_size/1048576}")
	log_pass "rojo build" "${build_size_mb} MB compiled"
else
	log_fail "rojo build" "exit $? — see /tmp/rojo-build.log"
fi
rm -f "$BUILD_OUTPUT"

# -------- 4. Phase 0 counter sites --------
section "4. Phase 0 — HttpApi counter instrumentation"

# Count HttpApiCounter.record() call sites (excluding comments + module declaration)
counter_sites=$(grep -rE '^\s*HttpApiCounter\.record\(' \
	src/ReplicatedStorage src/ServerScriptService src/StarterPlayer src/StarterPlayerScripts 2>/dev/null \
	| wc -l)
# Count unique bucket names (any quoted string passed to record())
counter_buckets=$(grep -rE 'HttpApiCounter\.record\(' \
	src/ReplicatedStorage src/ServerScriptService src/StarterPlayer src/StarterPlayerScripts 2>/dev/null \
	| grep -oE '"[^"]+"' | sort -u | wc -l)

# Handover claim: 18 sites, 17 unique buckets
# (Note: handover says 9 server + 3 client wrapper call sites; actual is 12 + 2 — see HANDOVER note to update)
if [[ $counter_sites -eq 18 ]]; then
	log_pass "counter sites" "18 (matches HANDOVER)"
else
	log_warn "counter sites" "$counter_sites (HANDOVER says 18 — drift of $((counter_sites - 18)))"
fi

if [[ $counter_buckets -eq 17 ]]; then
	log_pass "counter buckets" "17 unique (matches HANDOVER)"
else
	log_warn "counter buckets" "$counter_buckets unique (HANDOVER says 17 — drift of $((counter_buckets - 17)))"
fi

# -------- 5. Phase 2 wrapper migration --------
section "5. Phase 2 — HttpApi wrapper migration"

# Count server call sites using HttpApi.<func>( pattern (actual function calls, not counter checks)
server_sites=$(grep -rE 'HttpApi\.[a-zA-Z_]+\(' \
	src/ServerScriptService 2>/dev/null \
	| grep -vE 'ClientHttpApi|HttpApiCounter|Config\.HttpApi' \
	| wc -l)
# Count client call sites using ClientHttpApi.<func>( pattern (exclude the wrapper module file itself)
client_sites=$(grep -rE 'ClientHttpApi\.[a-zA-Z_]+\(' \
	src/StarterPlayer src/StarterPlayerScripts 2>/dev/null \
	| grep -v "Utils/ClientHttpApi\.luau" \
	| wc -l)
# Count wrapper functions defined
server_wrapper_funcs=$(grep -cE '^function HttpApi\.' \
	src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/HttpApi.luau 2>/dev/null)
client_wrapper_funcs=$(grep -cE '^function ClientHttpApi\.' \
	src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/ClientHttpApi.luau 2>/dev/null)

# Handover claim (line 2.4 / 2.5): 9 server sites, 3 client sites, 7 server funcs, 3 client funcs
# ACTUAL: 12 server sites, 2 client sites — handover undercounted; see HANDOVER §Note to update
if [[ $server_sites -eq 9 ]]; then
	log_pass "server call sites" "9 (matches HANDOVER)"
else
	log_warn "server call sites" "$server_sites (HANDOVER says 9 — drift of +$((server_sites - 9)))"
fi

if [[ $client_sites -eq 3 ]]; then
	log_pass "client call sites" "3 (matches HANDOVER)"
else
	log_warn "client call sites" "$client_sites (HANDOVER says 3 — drift of $((client_sites - 3)))"
fi

if [[ $server_wrapper_funcs -eq 7 ]]; then
	log_pass "server wrapper funcs" "7 (matches HANDOVER)"
else
	log_warn "server wrapper funcs" "$server_wrapper_funcs (HANDOVER says 7)"
fi

if [[ $client_wrapper_funcs -eq 3 ]]; then
	log_pass "client wrapper funcs" "3 (matches HANDOVER)"
else
	log_warn "client wrapper funcs" "$client_wrapper_funcs (HANDOVER says 3)"
fi

# -------- 6. Config toggles --------
section "6. Config toggles (default OFF = safe)"

config_file="src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau"
if [[ -f "$config_file" ]]; then
	# Filter out comment lines (start with optional whitespace + --) before extracting values
	httpapi_enabled=$(grep -v '^\s*--' "$config_file" | grep -E "^\s*ENABLED\s*=\s*" | head -1 | grep -oE "true|false" || echo "?")
	counters_enabled=$(grep -v '^\s*--' "$config_file" | grep -E "COUNTERS_ENABLED\s*=\s*" | head -1 | grep -oE "true|false" || echo "?")

	if [[ "$httpapi_enabled" == "false" ]]; then
		log_pass "Config.HttpApi.ENABLED" "false (wrapper bypassed, safe)"
	else
		log_warn "Config.HttpApi.ENABLED" "$httpapi_enabled (wrapper ACTIVE — verify this is intended)"
	fi

	if [[ "$counters_enabled" == "false" ]]; then
		log_pass "Config.HttpApi.COUNTERS_ENABLED" "false (telemetry off, zero overhead)"
	else
		log_warn "Config.HttpApi.COUNTERS_ENABLED" "$counters_enabled (telemetry ACTIVE)"
	fi
else
	log_fail "Config.luau" "not found at $config_file"
fi

# -------- 7. S1 short-circuit (Phase 1 sanity) --------
section "7. Phase 1 quick wins — sanity"

s1_shortcircuit=$(grep -v '^\s*--' "$config_file" 2>/dev/null | grep -E "S1_SHORTCIRCUIT\s*=\s*" | grep -oE "(true|false)" | head -1)
s2_debounce=$(grep -v '^\s*--' "$config_file" 2>/dev/null | grep -E "S2_DEBOUNCE_MS\s*=\s*" | sed -E 's/.*=\s*([0-9]+).*/\1/' | head -1)
rank_ttl=$(grep -v '^\s*--' "$config_file" 2>/dev/null | grep -E "^\s*RANK_CACHE_TTL\s*=\s*" | sed -E 's/.*=\s*([0-9]+).*/\1/' | head -1)
sync_poll=$(grep -v '^\s*--' "$config_file" 2>/dev/null | grep -E "^\s*SYNC_POLL_INTERVAL\s*=\s*" | sed -E 's/.*=\s*([0-9]+).*/\1/' | head -1)
re_ttl=$(grep -v '^\s*--' "$config_file" 2>/dev/null | grep -E "^\s*RE_CACHE_TTL\s*=\s*" | sed -E 's/.*=\s*([0-9]+).*/\1/' | head -1)
settle_delay=$(grep -v '^\s*--' "$config_file" 2>/dev/null | grep -E "^\s*GROUP_RANK_SETTLE_DELAY\s*=\s*" | sed -E 's/.*=\s*([0-9]+).*/\1/' | head -1)

[[ "$s1_shortcircuit" == "true" ]] && log_pass "S1_SHORTCIRCUIT" "true" || log_warn "S1_SHORTCIRCUIT" "$s1_shortcircuit"
[[ "$s2_debounce" == "1000" ]] && log_pass "S2_DEBOUNCE_MS" "1000" || log_warn "S2_DEBOUNCE_MS" "$s2_debounce"
[[ "$rank_ttl" == "300" ]] && log_pass "RANK_CACHE_TTL" "300s" || log_warn "RANK_CACHE_TTL" "${rank_ttl}s"
[[ "$sync_poll" == "30" ]] && log_pass "SYNC_POLL_INTERVAL" "30s" || log_warn "SYNC_POLL_INTERVAL" "${sync_poll}s"
[[ "$re_ttl" == "300" ]] && log_pass "RE_CACHE_TTL" "300s" || log_warn "RE_CACHE_TTL" "${re_ttl}s"
[[ "$settle_delay" == "15" ]] && log_pass "GROUP_RANK_SETTLE_DELAY" "15s" || log_warn "GROUP_RANK_SETTLE_DELAY" "${settle_delay}s"

# -------- Summary --------
if [[ $JSON -eq 1 ]]; then
	echo "{"
	echo "  \"pass\": $PASS_COUNT,"
	echo "  \"warn\": $WARN_COUNT,"
	echo "  \"fail\": $FAIL_COUNT,"
	echo "  \"results\": ["
	first=1
	for r in "${RESULTS[@]}"; do
		IFS='|' read -r status name detail <<<"$r"
		[[ $first -eq 0 ]] && echo ","
		first=0
		# Escape detail for JSON
		detail_json=$(printf '%s' "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g')
		printf '    {"status":"%s","name":"%s","detail":"%s"}' "$status" "$name" "$detail_json"
	done
	echo ""
	echo "  ]"
	echo "}"
else
	echo ""
	echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}Summary${NC}: ${GREEN}$PASS_COUNT pass${NC} · ${YELLOW}$WARN_COUNT warn${NC} · ${RED}$FAIL_COUNT fail${NC}"
	echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

	if [[ $FAIL_COUNT -eq 0 ]]; then
		echo -e "${GREEN}✓ Handover state is valid. Ready to publish.${NC}"
		echo ""
		echo "Next steps (see HANDOVER.md §Next steps):"
		echo "  1. Publish to staging (TELEMETRY_RUN_CHECKLIST.md §Step 1)"
		echo "  2. Toggle ON Phase 0: HttpApiTelemetry.Enable() in Command Bar"
		echo "  3. Run 30 CCU workload (1-2 days)"
		echo "  4. Capture + analyze (Task 0.7)"
		echo "  5. Phase 2.6 parallel-run verification"
		echo "  6. Phase 2.8 production promotion"
		exit 0
	else
		echo -e "${RED}✗ Validation failed. Fix issues above before publishing.${NC}"
		exit 1
	fi
fi
