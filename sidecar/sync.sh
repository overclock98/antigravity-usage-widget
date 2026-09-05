#!/usr/bin/env bash
# Antigravity Usage Sidecar — fetches real quota from Google's internal API
# and writes it to the Omarchy agents widget.
set -euo pipefail

USAGE_DIR="$HOME/.local/state/omarchy/agents/usage"
USAGE_FILE="$USAGE_DIR/antigravity.json"
mkdir -p "$USAGE_DIR"

# ── 1. Get a fresh access token from the system keyring ──────────────
KEYRING_JSON=$(secret-tool lookup service gemini 2>/dev/null || true)
if [ -z "$KEYRING_JSON" ]; then
  echo "No keyring entry found for gemini" >&2
  exit 1
fi

ACCESS_TOKEN=$(echo "$KEYRING_JSON" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['token']['access_token'])")

# ── 2. Hit the Google quota API ──────────────────────────────────────
API_RESPONSE=$(curl -sf -X POST \
  'https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: antigravity/1.11.3" \
  -d '{}' 2>/dev/null || true)

if [ -z "$API_RESPONSE" ]; then
  echo "Quota API request failed" >&2
  exit 1
fi

# ── 3. Transform the API response into the Omarchy agents schema ─────
python3 - "$API_RESPONSE" <<'PYEOF' > "$USAGE_FILE.tmp"
import sys, json, re
from datetime import datetime, timezone

raw = json.loads(sys.argv[1])
models = raw.get("models", {})

# Only show user-facing models people actually use
SKIP_PATTERNS = [
    r"^tab_",            # autocomplete internals
    r"^chat_",           # internal chat models
    r"-tiered$",         # duplicate tiered entries
]

seen = {}
limits = []

for name, info in sorted(models.items()):
    qi = info.get("quotaInfo", {})
    frac = qi.get("remainingFraction", 0.0)
    display = info.get("displayName", name)
    
    # Strip suffixes like (High), (Low), (Thinking) to group model families together
    display = re.sub(r'\s*\([^)]*\)\s*$', '', display)

    reset_time = qi.get("resetTime")

    # Skip internal models, models without quota, or pattern-matched
    if info.get("isInternal"):
        continue
    if any(re.search(p, name) for p in SKIP_PATTERNS):
        continue

    # Deduplicate by display name (keep the one with lowest remaining)
    if display in seen:
        if frac < seen[display]["frac"]:
            # Replace with worse quota
            for i, l in enumerate(limits):
                if l["label"] == display:
                    limits[i]["percent"] = round(1.0 - frac, 4)
                    if reset_time:
                        limits[i]["resetsAt"] = reset_time
                    break
            seen[display]["frac"] = frac
        continue

    seen[display] = {"frac": frac}
    limit_obj = {
        "label": display,
        "percent": round(1.0 - frac, 4)
    }
    if reset_time:
        limit_obj["resetsAt"] = reset_time
    limits.append(limit_obj)

# Group by family
from collections import defaultdict
families = defaultdict(list)
for l in limits:
    label = l["label"].lower()
    if "claude" in label or "gpt" in label:
        families["Claude/GPT"].append(l)
    else:
        families["Gemini"].append(l)

import os
usage_dir = os.path.expanduser("~/.local/state/omarchy/agents/usage")

# Remove old unified file if it exists
old_file = os.path.join(usage_dir, "antigravity.json")
if os.path.exists(old_file):
    os.remove(old_file)

for family, fam_limits in families.items():
    fam_limits.sort(key=lambda x: x["percent"], reverse=True)
    clean_name = family.lower().replace(" & ", "-").replace(" ", "-").replace("/", "-")
    prefix = "1-" if "gemini" in clean_name else "2-"
    fam_id = f"antigravity-{prefix}{clean_name}"
    output = {
        "schemaVersion": 1,
        "id": fam_id,
        "name": family,
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "ready": True,
        "limits": fam_limits
    }
    tmp_path = os.path.join(usage_dir, f"{fam_id}.json.tmp")
    final_path = os.path.join(usage_dir, f"{fam_id}.json")
    with open(tmp_path, "w") as f:
        json.dump(output, f, indent=2)
    os.rename(tmp_path, final_path)

PYEOF

# ── 4. Restore the native local trackers ─────────────────────────────
# We hijacked the Omarchy UI update timer to run this script.
# We must now call the original local tracker to ensure Claude Code, Codex, 
# and Fireworks continue tracking their local usage normally!
if command -v omarchy-agent-usage-update >/dev/null; then
  exec omarchy-agent-usage-update "$@"
fi
