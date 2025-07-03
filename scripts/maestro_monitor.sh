#!/usr/bin/env bash
set -euo pipefail

#── Config ──────────────────────────────────────────────────────────────────────
PR_NUM=${1:-8}                    # 🎻 movement we're conducting (default: 8)
INTERVAL=90                       # ⏲️  seconds between baton-checks
MAX_LOOPS=40                      #   (40×90 s ≈ 1 hr) – exit gracefully after that
OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

MAESTRO_CUE=$(cat <<'EOF'
@claude – Time to bring this movement into tune!  

**Current Dissonance (Failing Checks)**  
1. ❌ *Code Quality* – formatting / Credo issues  
2. ❌ *PR Description / Docs* – workflow step mis-fires  
3. ❌ *S4 Analyze Requests* – workflow error  
4. ❌ *Track Task Progress* – workflow error  

**Let's resolve the musical tension:**  
1. Run **`mix format`** on every changed file.  
2. Run **`mix credo --strict`** and address all warnings.  
3. Execute **`mix test`** until the suite is green.  
4. Verify the new *RateLimiter* mirrors *CircuitBreaker* (Task 1).  

The workflow failures can wait; quality comes first.  
🎯 *Goal:* all checks green ✅ → auto-merge → next movement.  
You're playing brilliantly—just a few bars to perfect intonation. 🎶
EOF
)

#── Post the initial cue (first baton-lift) ─────────────────────────────────────
# Check if we need to post a new cue or just monitor
LAST_AUTHOR=$(gh pr view "$PR_NUM" --json comments -q '.comments[-1].author.login // ""')
if [[ "$LAST_AUTHOR" != "jmanhype" ]]; then
  echo "🎼 Posting Maestro cue to PR #$PR_NUM…"
  gh pr comment "$PR_NUM" --body "$MAESTRO_CUE"
else
  echo "🎼 Maestro cue already posted, entering monitoring mode…"
fi

#── Baton-check loop ────────────────────────────────────────────────────────────
echo "🎼 Entering live-conduction loop (check every ${INTERVAL}s)…"
for ((i=1;i<=MAX_LOOPS;i++)); do
  sleep "$INTERVAL"

  echo -e "\n🎼 Check $i/$(printf '%d' "$MAX_LOOPS") – $(date '+%H:%M:%S')"
  
  # 1️⃣  Grab last comment author
  LAST_COMMENT_AUTHOR=$(gh pr view "$PR_NUM" --json comments \
                         -q '.comments[-1].author.login // ""')

  # 2️⃣  Check combined status for the head SHA
  SHA=$(gh pr view "$PR_NUM" --json headRefOid -q .headRefOid)
  COMBINED_STATE=$(gh api "/repos/$OWNER_REPO/commits/$SHA/status" \
                   -q .state)  # success / pending / failure

  echo "▪ Last comment author: $LAST_COMMENT_AUTHOR"
  echo "▪ Combined state    : $COMBINED_STATE"

  if [[ "$LAST_COMMENT_AUTHOR" == "claude" ]]; then
    echo "🎉 Claude has replied – baton passes back. Exiting loop."
    exit 0
  fi

  if [[ "$COMBINED_STATE" == "success" ]]; then
    echo "🥳 All checks green – movement resolved. Exiting loop."
    exit 0
  fi
done

echo "⚠️  Max monitoring time reached without resolution. Handing baton back."
exit 1