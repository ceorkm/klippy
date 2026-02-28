#!/bin/bash

# Klippy Build Script for Swift Package Manager

set -e

echo "🚀 Building Klippy..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
swift package clean

# Build the project
echo "🔨 Building project..."
swift build -c release

# Run tests
echo "🧪 Running tests..."
swift test

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "✅ Build completed successfully!"
    echo ""
    echo "To run Klippy:"
    echo "  swift run Klippy"
    echo ""
    echo "Or build and run in one command:"
    echo "  swift run"
else
    echo "❌ Build failed!"
    exit 1
fi
