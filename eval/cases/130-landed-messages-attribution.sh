# shellcheck shell=bash
# --- landed messages strip tool attribution, preserving human trailers and body text ------------------------
git checkout -qb fleet/c1-bean-ai
printf 'fix: attribution (bean-ai)\n\nBody mentions Cursor and stays unchanged.\n\n' > "$T/ai-message"
for tool in Cursor CLAUDE Codex Copilot OpenAI Anthropic ChatGPT agy OpenCode; do
  for trailer in Co-authored-by Generated-by Signed-off-by; do
    printf '%s: %s <agent@example.invalid>\n' "$trailer" "$tool" >> "$T/ai-message"
    printf '%s: Agent <%s@example.invalid>\n' "$trailer" "$tool" >> "$T/ai-message"
  done
done
for trailer in Co-authored-by Generated-by Signed-off-by; do
  printf '%s: Alice Example <alice@example.invalid>\n' "$trailer" >> "$T/ai-message"
done
echo attribution > src/ai.txt; git add src/ai.txt; git commit -q -F "$T/ai-message"
ai_source=$(git rev-parse HEAD)
echo second >> src/ai.txt; git add src/ai.txt
git commit -qm 'fix: second attribution (bean-ai)' -m 'co-AUTHORED-by: Cursor <cursoragent@cursor.com>'
git checkout -q main
out=$("$BIN"/fleet-land-bean bean-ai 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q '^LANDED bean-ai' <<<"$out" \
  && ! git log -2 --format=%B | grep -qiE '^(Co-authored-by|Generated-by|Signed-off-by):.*(cursor|claude|codex|copilot|openai|anthropic|chatgpt|agy|opencode)' \
  && ok 'land-bean strips tool names and emails from every cherry-picked message' || bad "land-bean tool attribution: $out"
human_trailers=$(git log -1 --format=%B HEAD~1 | grep -c ': Alice Example <alice@example.invalid>')
[ "$human_trailers" = 3 ] \
  && git log -1 --format=%B HEAD~1 | grep -qx 'Co-authored-by: Alice Example <alice@example.invalid>' \
  && git log -1 --format=%B HEAD~1 | grep -qx 'Body mentions Cursor and stays unchanged.' \
  && git log -1 --format=%B HEAD~1 | grep -q "$ai_source" \
  && ok 'land-bean preserves human attribution, body text and cherry-pick provenance' || bad 'land-bean changed non-tool message text'
git log -1 --format=%B "$ai_source" | grep -q '^Co-authored-by: Cursor ' \
  && ok 'land-bean leaves the source branch message unchanged' || bad 'land-bean modified the source commit'
