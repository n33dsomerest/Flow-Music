#!/bin/bash
set -e

echo "🚀 Initializing Git & Pushing to GitHub..."
git init
git add .
git commit -m "feat: initial commit for Flow Music ad-free streaming app"

# Set remote origin
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/n33dsomerest/Flow-Music.git

git branch -M main

echo "📤 Pushing to GitHub (main branch)..."
git push -u origin main

echo "✅ Push completed successfully!"
