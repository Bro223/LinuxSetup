#!/bin/bash
cd /home/aleks/MyScripts/LocalRepos/LinuxSetup
echo "=== GIT STATUS ==="
git status
echo ""
echo "=== GIT REMOTE ==="
git remote -v
echo ""
echo "=== RECENT LOG ==="
git log --oneline -5
echo ""
echo "=== WORKDIR ==="
pwd
