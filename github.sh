#!/bin/bash
git add .

if git diff --cached --quiet; then
  echo "No changes to commit"
else
  git commit -m "Efficiency Improved"
  git push
  echo "✅ Uploaded Successfully."
fi