#!/bin/bash
# Compiles the non-UI service layer together with Tests/main.swift and runs it.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)/tests"
swiftc -o "$OUT" -target arm64-apple-macos14.0 \
    Sources/Models/*.swift \
    Sources/Services/LibraryStore.swift \
    Sources/Services/MetadataCache.swift \
    Sources/Services/HTTPClient.swift \
    Sources/Services/SteamAPIService.swift \
    Sources/Services/AchievementCatalog.swift \
    Sources/Services/WalkthroughLinks.swift \
    Sources/Services/SteamWebSession.swift \
    Sources/Services/SecretStore.swift \
    Sources/Services/AppLog.swift \
    Sources/Services/GameFetcher.swift \
    Sources/Services/GameNameMatcher.swift \
    Sources/Services/FriendProfiles.swift \
    Sources/Services/SteamCommunityService.swift \
    Sources/Services/ImageLoader.swift \
    Sources/Components/CachedAsyncImage.swift \
    Tests/main.swift
"$OUT"
