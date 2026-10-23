# Achievement Hunter for macOS: feature details

### 1. ⚡ Instant 0-ms Launch & Persistent Local Cache
- Caches all fetched games, achievements, and player progress locally in `Application Support` in a **versioned, per-game layout** (`library/index.json` + `library/games/<appId>.json`). Only changed games are rewritten, a newer/unreadable cache is moved aside instead of being deleted, and the old single-file cache is migrated automatically.
- Next time you launch the app, it loads **instantly** without waiting for the network, silently refreshing changes in the background.

### 2. ⌨️ macOS Keyboard Shortcuts
- `⌘ 1` ... `⌘ 9`: Switch between sections (same order as the sidebar):
  1. Games Library
  2. Now Playing
  3. Activity Feed
  4. Road to 100%
  5. Focus Targets
  6. Analytics & Heatmap
  7. Hall of Fame
  8. Friend Compare
  9. Widgets Studio
- **Sidebar**: each navigation group (Library, Hunt, Insights, Share & Compare) and the game list can be collapsed with the chevron on its header, so the game list can use the whole height. Collapsed groups keep their icons on the header line; your choice is remembered. Insights and Share & Compare start collapsed.
- `⌘ K`: **Quick open**: type to jump to any game, section or action (↑/↓, ⏎).
- `⌘ F`: search your games. `⌘ [` / `⌘ ]`: back / forward through where you've been.
- `⌘ ⇧ P`: share your profile card.
- `⌘ R`: Instant sync with Steam.
- `⌘ ⇧ E`: Quick export complete library report to Markdown.
- `⌘ ,`: Open Preferences & Settings.

### 3. 📤 Export to Markdown & CSV
- **Markdown (`.md`)**: Generates an aesthetic backlog report formatted with checkboxes `[x]` / `[ ]` and rarity tiers, ready for **Obsidian** or **Notion**.
- **CSV (`.csv`)**: Exports your complete game completion metrics for **Excel** or Google Sheets.

### 4. 📳 Trackpad Haptic Feedback
- Subtle native tactile feedback (`NSHapticFeedbackManager`) when pinning grinding targets, assigning tags, or copying graphic cards.

### 5. 🍎 macOS System & Native Integrations
- **Menu Bar Extra (`MenuBarExtra`)**: Companion in your macOS menu bar (`trophy.fill` icon) showing active game completion, recent unlocks, and quick launcher.
- **Widgets Studio**: In-app *previews* of widget designs (*Rarest Trophy Showcase*, *Perfectionist Streak*, *Active Game Progress Bar*). These are not installed system widgets yet (no WidgetKit extension).
- **Sign in with Steam, no API key**: you sign in on Steam's own page; the app asks Steam for the session's short-lived API token and uses it to load your whole library (even with private game details). Your login is kept in an encrypted file for this Mac and the token is renewed automatically. The only two ways in are **Sign in with Steam** or a **Steam Web API key** (plus your profile). There is no anonymous "public profile" mode any more: Steam no longer shows game lists to signed-out visitors, so it could only ever find a handful of showcased games.
- **Start guide**: first launch walks you through signing in, preferences, the first sync and shortcuts; reopen it from Settings or `⌘ K`.

### 6. 🎯 Achievement Hunting & Completionist Tools
- **"Road to 100%" (Almost There)**: Isolates games closest to completion ($60\%\text{--}99\%$) with expandable remaining locked achievements.
- **Focus Targets (Grinding Dashboard)**: Pin $3\text{--}5$ specific achievements across games with custom strategy notes.
- **Walkthrough Links**: Direct 1-click links on any achievement card to YouTube walkthrough videos, Steam Community Guides, and Google solutions.
- **Achievement Tags**: Tag achievements as `Missable`, `Multiplayer`, `Difficulty`, `Grind`, or `Story`.

### 7. 📊 Analytics, Heatmap & Visualizations
- **Unlock Activity Heatmap**: Interactive GitHub-style 52-week calendar heatmap showing daily unlock frequency and active streaks.
- **Trophy Hall of Fame**: An all-time podium showcasing your Top 3 all-time rarest achievements plus a Top 20 gallery across your Steam history (<3% global rarity).
- **Perfectionist Milestones**: Milestone progression badges tracking your path to 5, 10, 25, 50, and 100 perfected games.

### 8. 🎨 Sharing & Social Features
- **Sharable Achievement & 100% Cards**: four templates (Classic, Spotlight 16:9, Poster 4:5, Minimal light) exported as high-res PNG.
- **Profile Share Card** (Exophase style): *Hunter Card* (stats + game cover grid), *Rarest Trophies*, *Compact*. Sidebar → Share Profile Card or `⌘ ⇧ P`.
- **Friend Head-to-Head Comparison**: Real data. Lists your Steam friends and compares achievement counts on the games you both own. Requires a Steam Web API key and a public friends list / game details.
- **Discord status text (`DiscordRPCService`)**: Formats your hunting status for you to copy. It does not connect to Discord (no Rich Presence).

### 9. 🔄 Full-Library Sync
- Syncs achievements for **every** game (no cap), 6 requests at a time, with Retry-After aware backoff on Steam rate limits (HTTP 429).
- The library appears first; achievements stream in with a non-blocking progress banner (Stop button). Totals update as games load.
- Games that fail show the reason and a **Retry** button (per game, or "Retry failed" for all). A failed refresh never erases data you already had.

### 10. 🧩 Steam Achievement Sets (the new achievements system)
- Reads Steam's public achievement catalog (`IPlayerService/GetGameAchievements`, no API key) which exposes **Achievement Sets**, **DLC sets** and **archived** achievements, and merges it with your unlock state. It is schema-driven, so games that add or reorganise sets later show up automatically (the catalog is re-checked every 2 days; *Full Re-sync* forces it).
- Completion follows Steam's rules: archived achievements you missed don't count, DLC sets don't count until you have access (you've unlocked something in them, or right-click the set and choose *I own this DLC*), developer-only sets never count.
- Game pages get a row of **set cards** with progress bars (DLC in purple, archived badge); click one to filter the list. Achievement cards show their set / DLC / archived badge.

### 11. ⚡ Incremental Sync & Caches
- Per-game unlocks come from Steam's own player endpoint (`IPlayerService/GetUserAchievements`, the one Steam's new achievements page uses), authorised by your sign-in. It is one light request per game, includes Achievement Set data, and works where the old stats pages no longer do.
- Normal syncs (`⌘ R`) refetch only games whose playtime changed, that never loaded or failed, or that are over 24 h old. *Settings > Full Re-sync* refetches everything.
- Achievement schema (14 days) and global rarity (3 days) are cached on disk, so a refresh needs 1 request per game instead of 3. Stale cache is used if Steam is unreachable.
- Cover art and icons use a bounded memory cache plus a 400 MB disk cache (LRU), downsampled on decode.
- With an API key, profile and library come from the official Web API (no page scraping). Signed in, the library comes through your Steam session; unknown playtime shows as "Playtime unknown" and placeholder names are replaced from the public store.

### 11a. 🔑 What works without an API key
Signing in with Steam is enough for everything. The sign-in token covers: your library, per-game unlocks (`GetUserAchievements`), batch unlock counts, your friends list (`IFriendsListService`), friends' libraries, and friends' unlocks. Names and avatars come from Steam's public mini profile instead of `GetPlayerSummaries`, live status from the mini profile, game data and rarity from the public catalog. An API key is only an alternative for people who prefer not to sign in.
- Steam's community pages are rate limited (a burst gets "403 Access Denied" for a while). All requests to them go through one gate that spaces them out and stops completely during a cool-down, instead of retrying.

### 11b. 🔁 Automatic Sync
- While the app is open it syncs silently in the background (default **every 10 minutes**, configurable in Settings: off / 5 / 10 / 15 / 30 / 60). It also catches up right after launch and whenever you switch back to the app.
- One batch request compares the unlock count of every game with what is saved and refetches only the games that differ, so a background sync usually costs a handful of requests and no overlay.
- The game you are playing is refreshed about every 2 minutes through Now Playing.

### 12. 🔔 Activity Feed & Notifications
- Every sync is diffed against the previous one; newly unlocked achievements go to the **Activity Feed** (unseen badge in the sidebar) and trigger a macOS notification (toggle in the feed). The first sync only sets a baseline.
- While you are in a game, the live game is re-checked about every 2 minutes.

### 13. 🙈 Hide games without achievements
- Toggle in the sidebar and Settings (on by default). Games that have no achievements are hidden from the list and statistics and are **not re-synced** (re-checked every 3 weeks in case the developer adds some). A game with no achievements costs one cheap request the first time.

### 14. 📖 Walkthroughs
- Game banner → *Walkthroughs*: TrueSteamAchievements walkthrough page for the game (`truesteamachievements.com/game/<Title>/walkthrough`), a site search, Steam guides and YouTube. Each achievement card has the same menu with *Find This Achievement* (TrueSteamAchievements doesn't publish stable per-achievement URLs, so achievement links go through a site-restricted search). The game URL is built from the title and can 404 if TrueSteamAchievements names the game differently; use the search item then.

### 15. ⚡ Performance
- The library is on screen about 2 ms after launch (index only); achievements load in the background (about 0.1 s for 1,500 games).
- Per-game progress counts, filtered/sorted lists and totals are cached, and sync results are applied in batches, so a big sync no longer redraws the app once per game.
- Image downloads are capped at 8 at a time; the disk cache is LRU-bounded.

### 16. 🔐 Privacy & Security
- Your Steam Web API key and Steam session cookies are stored in `Application Support/AchievementHunter/secrets.bin`: AES-256-GCM encrypted, owner-only permissions, key derived from this Mac's hardware ID (so a copied backup can't be read elsewhere). It deliberately does **not** use the macOS Keychain: the app is signed ad hoc, so macOS asked for your login password after every update. A key left in preferences by an older version is migrated automatically.
- Signing out removes the key, cookies, cached library and web data. Pinned targets and tags are kept (they are your own notes); pins are cleared if you later sign in as a different account.
- App Transport Security is on (HTTPS only). The app never registers an API key for you; sign-in only *reads* a key you already created at steamcommunity.com/dev/apikey.
- If an older version stored your login in the Keychain, that item is simply left unused (the app never reads it, so no prompt); you sign in again once. You can delete the "com.achievementhunter.mac" entry in Keychain Access.

---

## 📦 Installation (.dmg)

The ready-to-use disk image is located in the project root:

```bash
AchievementHunter.dmg
```

1. Double-click `AchievementHunter.dmg` to open it.
2. Drag **Achievement Hunter** into the **Applications** folder.
3. Launch **Achievement Hunter**.

> **Note for macOS Gatekeeper**: Because the app is compiled locally without a paid Apple Developer ID certificate, right-click the app in `/Applications` and choose **Open** on the first launch.

---

## 🛠 Rebuilding from Source

You can recompile the app bundle and rebuild the `.dmg` anytime with:

```bash
./scripts/build.sh
```

Run the service-layer tests (cache migration, HTTP retry/rate limits, API parsing, caching) with:

```bash
./scripts/run_tests.sh
```

## Plan, notifications, recap and friends

- **Road to 100%** has three tabs: *Almost There* (with a rough "~X h left at your pace"), *Quick Wins* (the easiest locked achievements across all games, most common first) and *Today's Plan* (one game to finish today, changing daily, with three achievements to start with).
- **Notifications** (Settings > Notifications): quiet hours, one daily summary instead of a banner per unlock, and a bigger celebration (in-app card plus special banner) for ultra-rare unlocks. The threshold is configurable.
- **Settings** are split into Account, Library, Notifications and Advanced tabs.
- **Your Year** share card (profile share sheet > "Your Year"): unlocks per month, rarest unlock, games finished, busiest month.
- **Friends**: star up to 5 favorite friends to see what they are playing and get an alert when they unlock something rare (under 5%) or finish a game you also own. Checked every 10 minutes with a few light requests; it stops when Steam's community pages start refusing. "Compare several friends at once" shows up to 4 friends side by side.
