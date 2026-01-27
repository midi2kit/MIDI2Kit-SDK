#!/bin/bash
# MIDI2Kit commit script - 2026-01-27 19:03

cd /Users/hakaru/Desktop/Develop/MIDI2Kit

# Show status
echo "=== Git Status ==="
git status

# Add all changes
echo ""
echo "=== Adding files ==="
git add -A

# Show what will be committed
echo ""
echo "=== Files to commit ==="
git diff --cached --stat

# Commit
echo ""
echo "=== Committing ==="
git commit -m "fix: CI11 parser headerSize=0 rejection, add BLE MIDI analysis docs

- Fix CI11 parser to reject headerSize=0 (prevents misidentification of CI12 multi-chunk)
- Add BLE-MIDI-PacketLoss-Analysis.md documenting physical layer reliability issues
- Add KnownIssues.md tracking all known issues and their status
- Update ClaudeWorklog20260127.md with debugging session notes

Root cause identified: BLE MIDI packet loss causes chunk 2/3 to be dropped ~90% of the time.
This is a physical layer limitation, not a software bug."

# Push
echo ""
echo "=== Pushing ==="
git push origin main

echo ""
echo "=== Done ==="
