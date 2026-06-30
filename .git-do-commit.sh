#!/bin/bash
cd /home/aleks/MyScripts/LocalRepos/LinuxSetup
git add ProblemSolvingNotes/
# Also add the temp scripts in the repo root if you want them tracked
git add .git-*.sh
git status
echo "---"
echo "If everything looks good:"
echo "  git commit -m 'Add ProblemSolvingNotes - system troubleshooting docs + hibernate approach'"
echo "  git push"
echo ""
echo "Then clean up temp scripts:"
echo "  rm .git-*.sh"
