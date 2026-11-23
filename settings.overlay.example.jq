# Optional jq filter install.sh runs on claude-local's settings.json after the JSON overlay merge.
# Copy to ~/.config/small-model-skills/settings.overlay.jq. Keep it idempotent.
# Example: drop SessionStart hooks whose command mentions a tool a small model does not need.
(.hooks.SessionStart // empty) |= (
  map(.hooks |= map(select((.command // "") | test("example-tool-a|example-tool-b") | not)))
  | map(select((.hooks | length) > 0))
)
