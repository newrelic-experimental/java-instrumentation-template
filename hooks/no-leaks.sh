#!/usr/bin/env bash
# no-leaks.sh — blocks sensitive data, binary assets, and build artifacts
# Sections:
#   1. Blocked file types  — images, build output, logs, .env, real config files
#   2. Content scans       — passwords, usernames, tokens, hostnames, IPs, keys, JWTs, DB URLs
#
# Per-repo config files (place in repo root):
#   .no-leaks-ignore  — regex patterns for file paths to skip in Section 1 (one per line)
#   .no-leaks-safe    — regex patterns appended to the SAFE allowlist for content scans (one per line)
#
# Inline suppression — add to the end of any flagged line:
#   // no-leaks:ignore     (Java, Go, JS, TS)
#   # no-leaks:ignore      (Python, Shell, YAML, Properties)
#   /* no-leaks:ignore */  (Java block, CSS)

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

FOUND=0
REPORT=()

STAGED_FILES=$(git diff --cached --name-only)

flag_file() {
    local label="$1"
    local file="$2"
    REPORT+=("  ${RED}[$label]${NC} $file")
    FOUND=1
}

flag_content() {
    local label="$1"
    local line="$2"
    REPORT+=("  ${RED}[$label]${NC} $line")
    FOUND=1
}

# ── Per-repo ignore list (.no-leaks-ignore) ───────────────────────────────────
# Each line is a regex pattern for file paths to skip in Section 1.
# Lines starting with # or empty lines are ignored.
# Example: package-lock\.json

PRE_COMMIT_IGNORE=()
if [ -f ".no-leaks-ignore" ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#|^[[:space:]]*$ ]] && continue
        PRE_COMMIT_IGNORE+=("$line")
    done < ".no-leaks-ignore"
fi

is_ignored() {
    local f="$1"
    for pattern in "${PRE_COMMIT_IGNORE[@]}"; do
        if echo "$f" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# ── Section 1: Blocked file types ─────────────────────────────────────────────

while IFS= read -r f; do
    [ -z "$f" ] && continue

    # Skip files listed in .no-leaks-ignore
    is_ignored "$f" && continue

    # Exception: Gradle wrapper jar is intentionally tracked for supply-chain integrity
    if echo "$f" | grep -qE '^gradle/wrapper/gradle-wrapper\.jar$'; then
        continue
    fi

    # Images and screenshots
    if echo "$f" | grep -qiE '\.(png|jpg|jpeg|gif|bmp|tiff|ico|webp|svg)$'; then
        flag_file "IMAGE/SCREENSHOT" "$f"
    fi

    # Compiled / packaged build output
    if echo "$f" | grep -qiE '^build/|^target/|\.jar$|\.class$|\.war$|\.ear$|\.zip$'; then
        flag_file "BUILD ARTIFACT" "$f"
    fi

    # Gradle/Maven cache and wrapper jars
    if echo "$f" | grep -qiE '^\.gradle/|gradle/wrapper/gradle-wrapper\.jar$'; then
        flag_file "BUILD CACHE" "$f"
    fi

    # Log files
    if echo "$f" | grep -qiE '\.log$|^logs/'; then
        flag_file "LOG FILE" "$f"
    fi

    # .env files (environment variable files with real values)
    if echo "$f" | grep -qiE '(^|/)\.env(\.|$)'; then
        flag_file "ENV FILE" "$f"
    fi

    # Real config files — only templates should be committed
    if echo "$f" | grep -qiE '(^|/)config\.properties$|(^|/)application\.(properties|yml|yaml)$'; then
        flag_file "CONFIG FILE" "$f  ← commit .template version only, never the real config"
    fi

done <<< "$STAGED_FILES"

# ── Section 2: Content scans ──────────────────────────────────────────────────

DIFF=$(git diff --cached | grep "^+" | grep -v "^+++")

# Safe patterns — these are never flagged even if they match a scan pattern
SAFE='(YOUR_[A-Z_]+|<[-A-Za-z0-9_ ]+>|PLACEHOLDER|localhost|127\.0\.0\.1|0\.0\.0\.0|example\.(com|org|net)|newrelic\.com|nr-data\.net|maven\.org|gradle\.org|plugins\.gradle\.org|github\.com|githubusercontent\.com|squareup\.com|slf4j\.org|qos\.ch|apache\.org|google\.com|googleapis\.com|shields\.io|opensource\.newrelic\.com|xmlsoap\.org|w3\.org|sap\.com|\[a-zA-Z\])'

# Per-repo safe patterns (.no-leaks-safe) ─────────────────────────────────────
# Each line is a regex pattern appended to the SAFE allowlist.
# Lines starting with # or empty lines are ignored.
# Example: nr-ext\.net
if [ -f ".no-leaks-safe" ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#|^[[:space:]]*$ ]] && continue
        SAFE="$SAFE|$line"
    done < ".no-leaks-safe"
fi

scan() {
    local label="$1"
    local pattern="$2"
    local matches
    matches=$(echo "$DIFF" | grep -iE -- "$pattern" | grep -viE -- "$SAFE" | grep -v 'no-leaks:ignore')
    while IFS= read -r line; do
        [ -n "$line" ] && flag_content "$label" "$line"
    done <<< "$matches"
}

# Passwords — non-empty assignment
scan "PASSWORD" \
    '(^|[^a-zA-Z])(password|passwd|SAP_PASS|j_password)\s*[=:]\s*\S{4,}'

# Usernames — non-empty assignment (properties, env vars, shell scripts)
scan "USERNAME" \
    '(\$SAP_USER\s*=\s*["\x27]|sappo\.username\s*=\s*|SAPPO_USERNAME\s*[=:]\s*|j_username\s*=)[A-Za-z0-9_@.]{3,}'

# Tokens and API keys
scan "TOKEN/API KEY" \
    '(token|api_key|apikey|insertKey|insert_key|secret_key|access_key|NR_INSERT_KEY|auth_key|bearer)\s*[=:]\s*["\x27]?[A-Za-z0-9._\-]{10,}'

# Hostname/domain — SAP_ prefixed vars, sappo.* properties, and generic host/url/endpoint keys
scan "HOSTNAME/DOMAIN" \
    '(\$?SAP[_A-Z0-9]*|sappo\.[a-z]+|[^a-zA-Z]host|baseUrl|base_url|endpoint|serverUrl|server)\s*[=:]\s*["\x27]?[a-zA-Z0-9][a-zA-Z0-9\-]{2,}\.[a-zA-Z0-9\-]{2,}\.[a-zA-Z]{2,}'

# Hardcoded HTTP/HTTPS URLs — catches hostnames embedded in code, scripts, or config
scan "HARDCODED URL" \
    'https?://[a-zA-Z0-9][a-zA-Z0-9\-]{2,}\.[a-zA-Z0-9\-]{2,}\.[a-zA-Z]{2,}'

# Private IP addresses
scan "PRIVATE IP" \
    '\b(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b'

# Generic secrets
scan "SECRET" \
    '(client_secret|private_key|aws_secret|azure_key|gcp_key|db_password|database_password|SAPPO_AES_KEY|sappo\.aeskey|aes_key)\s*[=:]\s*\S{8,}'

# SSH private key headers
scan "SSH PRIVATE KEY" \
    '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'

# JWT tokens — three base64url segments
scan "JWT TOKEN" \
    'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'

# Database connection strings
scan "DB CONNECTION STRING" \
    '(jdbc:[a-zA-Z]+://|mongodb(\+srv)?://|postgresql://|mysql://|redis://|sqlserver://)[^ "]{8,}'

# New Relic account IDs — JSON format and env var format
scan "NR ACCOUNT ID" \
    '("accountId[s]?":\s*\[?[1-9][0-9]{4,}\]?|NR_ACCOUNT_ID\s*[=:]\s*[1-9][0-9]{4,}|newrelic\.accountId\s*=\s*[1-9][0-9]{4,})'

# Internal environment identifiers — short uppercase codes on env-related keys
# Uses its own allowlist so generic names (PROD, DEV, UAT etc.) are not flagged
ENV_SAFE='(PROD(UCTION)?|DEV(ELOPMENT)?|TEST(ING)?|UAT|STAGING|STAGE|LOCAL|SANDBOX|YOUR_[A-Z_]+|<[-A-Za-z0-9_ ]+>)'
ENV_MATCHES=$(echo "$DIFF" \
    | grep -iE -- '(app\.env|APP_ENV|environment|[^a-zA-Z]env)\s*[=:]\s*[A-Z]{2,6}\b' \
    | grep -viE -- "$ENV_SAFE" \
    | grep -v 'no-leaks:ignore')
while IFS= read -r line; do
    [ -n "$line" ] && flag_content "INTERNAL ENV NAME" "$line"
done <<< "$ENV_MATCHES"

# ── Report ────────────────────────────────────────────────────────────────────

if [ $FOUND -eq 1 ]; then
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   NO-LEAKS CHECK FAILED                            ║${NC}"
    echo -e "${RED}║   Sensitive data or blocked files detected         ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    for item in "${REPORT[@]}"; do
        echo -e "$item"
    done
    echo ""
    echo -e "${YELLOW}Rules:${NC}"
    echo -e "  Credentials   → use placeholders: YOUR_USERNAME / YOUR_PASSWORD / YOUR_TOKEN"
    echo -e "  Hostnames     → use placeholders: YOUR_HOST"
    echo -e "  Images/PNGs   → do not commit screenshots or binary assets"
    echo -e "  Build output  → add build/ and *.jar entries to .gitignore"
    echo -e "  Config files  → commit config.properties.template only, never config.properties"
    echo -e "  .env files    → never commit — use environment variables at runtime"
    echo -e "  Suppress line → add // no-leaks:ignore or # no-leaks:ignore at end of line"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ no-leaks scan passed — no sensitive data or blocked files detected${NC}"
exit 0
