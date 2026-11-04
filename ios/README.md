# Canary for iPhone

A native SwiftUI app for the Canary board, designed to Apple's Human Interface
Guidelines and modelled on Health (Summary, Browse and the iPhone Duo sidebar),
Weather (the World State hero and its gauge) and Stocks (pinned signals with
sparklines and level pills). It reads the same public, read-only API as the
website, so the scheduled assessment needs no changes to feed it.

## Requirements

- **Xcode 27.1 or later** for the full app. The iPhone Duo sidebar uses an
  iOS 27 API and the fold-aware columns an iOS 27.1 one, and the iPhone Duo
  simulator needs the iOS 27.1 runtime.
- **Xcode 27.0 and 26.6 also build it**, without those two iPhone Duo
  refinements. The iOS 27 calls are fenced by SwiftUI's module version, and CI
  builds with all three Xcodes on every push.
- Deploys to **iOS 26.0 and later**: every iPhone that runs iOS 26, from
  iPhone 11 / SE (2nd gen) onwards.

## Run it

1. Open `ios/Canary.xcodeproj`.
2. Choose the **Canary** scheme and any iPhone simulator, including **iPhone Duo**,
   then press Run. No signing team is needed for the simulator.
3. To test Canary+ purchases in the simulator, nothing else is needed: the scheme
   uses `Config/Canary.storekit`, a local StoreKit configuration.
4. For a real device: select your team under *Signing & Capabilities* for both
   targets. Xcode registers the App Group `group.com.danleech.canary`
   automatically.

Debug builds accept launch arguments (scheme › Arguments) that open a screen
directly, for screenshots and UI checks: `-CanaryTab browse`,
`-CanaryRoute canary://signal/oil`, `-CanarySheet plus`, `-CanaryPins oil,ftse`.
See `Canary/App/DebugLaunch.swift`. They are compiled out of release builds.

## What's in it

| Area | Files | Notes |
| --- | --- | --- |
| Summary tab | `Canary/Summary` | World State hero, Pinned, On Alert, Changed in the last 24 hours, Situations |
| Browse tab | `Canary/Browse` | Domains → signals. In the sidebar on iPhone Duo, every domain is listed directly |
| Changes tab | `Canary/Changes` | Status changes by day, filterable |
| Search tab | `Canary/Search` | Signals, domains, situations |
| Signal detail | `Canary/Detail` | Level, chart of recent checks (Swift Charts), why, what it means for you, how the level was set, thresholds, sources |
| Canary+ | `Canary/Plus`, `Canary/Stores/PlusStore.swift` | StoreKit 2, Apple's `SubscriptionStoreView` |
| Alerts | `Canary/Alerts` | Background app refresh + local notifications |
| Siri & Shortcuts | `Canary/Intents`, `Shared/Intents` | World State, check a signal, list alerts, open a signal |
| Widgets | `CanaryWidgets`, `Shared/Widgets` | World State (free), Signal and Pinned (Canary+); Home Screen, Lock Screen, StandBy. The views live in `Shared/Widgets` so the app can draw them too |
| Data layer | `Shared/Model`, `Shared/Networking` | Codable models of `api/v1/*.json` and `data/history.json`, offline cache in the App Group |
| App icon | `Tools/make_icon.py` | Draws the light, dark and tinted icons from vector shapes |
| Tests | `CanaryTests`, `CanaryUITests` | Unit tests of the router and chart statistics; UI tests of touches, pickers, scrolling, sheets and purchases |
| App Store | `AppStore/` | Metadata, review notes, privacy and age-rating answers, screenshot generator |
| CI | `ci/`, `../.github/workflows/ios.yml` | Builds, tests and screenshots every push to the `ios-app` branch |

`Shared/` is compiled into both the app and the widget extension. The project
uses Xcode's synchronized folders, so new files are picked up automatically.

## Design rules followed

- **Standard containers only**: `TabView` with `Tab` and `TabSection`,
  `NavigationStack`, `NavigationSplitView`, `List`, `Form`, toolbars, sheets and
  the system search tab. This is what gives the app Liquid Glass bars, and what
  lets iOS move them into iPhone Duo's vertical bar and keep everything clear of
  the camera and the fold.
- **iOS 26 conventions**: glass ✕ and ✓ buttons in sheets (`Button(role: .close)`,
  `.confirm`), toolbar items grouped by the system, and the signal's name moving
  into the bar only once its large header scrolls away.
- **System typography and colours**: Dynamic Type text styles throughout, semantic
  colours, light and dark mode, accent colour only for interactive elements.
- **Colour is never the only cue** (charter §6): every level has its own symbol
  (octagon, triangle, circle, dashed circle) and its name in text. Badge colours
  meet WCAG AA contrast.
- **Accessibility**: VoiceOver labels for every row and card, an audio graph for
  charts, and layouts that stack at accessibility text sizes.
- **Honesty**: the AI-assessment disclosure, basis (measured, published or AI
  judgement) and the not-advice disclaimer appear in the app as on the website.

## Visual design

Modelled on Health: tiles on the grouped background, each washed with its
category's colour, coloured headers, rounded continuous corners, and a chart
wherever the data suits one.

- **Palette** (`Shared/Design/Palette.swift`): Apple's system colours. Red,
  orange and green mean attention levels and nothing else, so the 11 domains take
  blue, indigo, teal, purple, brown, cyan, mint and three soft custom tones. Text
  in a colour uses Apple's increased-contrast variant, so it meets WCAG AA in
  light and dark mode.
- **Gradients and glass**: a pastel mesh gradient behind the World State in its
  band's colours (also on the World State widget), soft washes at the top of each
  page and on tiles, and Liquid Glass for the level chips and chart callouts.
  Glass stays on small controls, as the HIG asks, not on whole content cards.
- **Charts fitted to the data** (`Canary/Charts`):

  | Data | Chart |
  | --- | --- |
  | World State score | Activity-style ring |
  | World State over time | Smoothed line over a gradient, band edges marked |
  | Levels today | Donut |
  | Levels by day | Stacked columns |
  | Moves up and easings by day | Diverging columns |
  | Domain scores | Horizontal bars in domain colours |
  | How levels were set | Donut (measured, published, AI judgement) |
  | How long each signal has held its level | Scatter by domain, shaped by level |
  | A signal's key value | Smoothed line with a range picker and touch-to-inspect |
  | A signal's level over time | Sleep-stage style timeline |
  | Pinned and domain signals | Mini line or level columns in each tile |

- Chart figures come from `Shared/Model/BoardStats.swift`, which derives them
  from the published check history only.

## Every iPhone, including iPhone Duo

Layouts follow size classes and the width actually available, never device models.

| Display | Size classes | What the app does |
| --- | --- | --- |
| Any iPhone, portrait | compact × regular | One column, tab bar at the bottom |
| Any iPhone, landscape | compact or regular × compact | Two columns where both fit at 300 pt; Browse becomes a split view on Plus and Pro Max |
| iPhone Duo, closed | compact × regular | One column; iOS moves the bars into the vertical strip at the side |
| iPhone Duo, closed, landscape | regular × compact | Bars in the vertical strip on the leading edge; overflow menu for toolbar buttons |
| iPhone Duo, open | regular × regular | **Sidebar, as in Health**: Summary, Changes, Search, then every Browse item. Two columns where they fit beside it |
| iPhone Duo, half folded like a book | regular × regular | Same; with Xcode 27.1 the column gutter sits on the hinge when it falls between two usable columns |

Folding or unfolding keeps the same screen open: `Router.adapt(usesSidebar:)`
moves the selection, and anything pushed on it, between the Browse tab and the
sidebar items. `Canary/Common/AdaptiveColumns.swift` does the column reflow in a
single layout pass.

## Verification

Every push to `ios-app` runs `.github/workflows/ios.yml` on GitHub's macOS
runners:

- builds Debug (simulator) and Release (device, unsigned) with Xcode 27.1, and
  Debug with Xcode 27.0 and 26.6;
- prints the SDK declarations of the iOS 26/27 APIs the app relies on
  (`ci/api_probe.sh`);
- installs the app on iPhone 17e, 17, Air and 18 Pro Max (iOS 27.0) and
  screenshots every screen in light, dark and accessibility text sizes;
- on iPhone Duo (iOS 27.1) moves the hinge through closed, closed landscape,
  open, open portrait, book and tabletop poses and screenshots each one, then
  folds and unfolds with the app running to check it keeps your place. Posing
  uses the third-party `hinge` CLI and `duo_pose.py` (both MIT), because Apple's
  `simctl` has no fold command;
- runs the unit tests (`CanaryTests`: router fold and unfold mapping, deep
  links, chart statistics, withheld figures) and the UI tests (`CanaryUITests`:
  tabs, search, chart touch and range picker, scroll titles, pinning, withheld
  figures, Settings, the purchase screen with a StoreKit test session, and the
  widget gallery) on iPhone 17 and on iPhone Duo's outer display;
- composes the captioned App Store screenshots (`AppStore/make_screenshots.py`)
  and uploads them as the `app-store-screenshots` artifact.

The debug launch arguments in `Canary/App/DebugLaunch.swift` open any screen
directly; `-CanarySheet widgets` and `-CanarySheet showcase` draw every widget
with the widget extension's own views, so the widgets can be screenshotted.

Not covered by CI: widgets on a real Home Screen, Siri, background alerts
arriving, VoiceOver, and anything on a physical device. Purchases are checked
only as far as the purchase screen loading its products.

## Before the App Store

- **Apple Developer Program** membership (£79 / $99 a year) and an App Store
  Connect record with bundle ID `com.danleech.canary`.
- **Canary+ products**: two auto-renewable subscriptions in one group,
  `com.danleech.canary.plus.yearly` and `com.danleech.canary.plus.monthly`. The
  prices in `Canary.storekit` (£14.99 a year, £1.99 a month) are placeholders.
- **Privacy policy** is live at `https://canary.danleech.com/privacy` and linked
  from the site's footer, Settings and the purchase screen. It doesn't yet name
  the data controller or give a contact address; UK GDPR expects both, so add
  them. `PrivacyInfo.xcprivacy` declares no tracking and no collected data.
- **Market data licences — decide before charging**: about ten measured signals
  show values built from Yahoo Finance (whose terms rule out commercial use) or
  from ICE BofA and Cboe series on FRED that carry redistribution limits:
  `equity-stress`, `ftse`, `bond-volatility`, `credit-spreads`, `dollar`, `gold`,
  `yen-carry`, `oil`, `eu-gas` and others that fall back to them
  (`scripts/fetch_metrics.py`, `RESTRICTED_*`). The free website gets by on
  derived values; a paid app is a different footing. The app now shows only the
  level for these signals: no figure, chart values or rubric number, and a
  "Figures Not Shown" note linking to the website (`Shared/Model/RestrictedData.swift`
  reads the licence notes in `data/metrics.json`, with a built-in list as a floor).
  The assessment text (`summary`, `state`) can still quote a price as news, for
  example "Brent near $104". Whether that's acceptable is a judgement for you or
  a lawyer; the alternatives are licensing the data or moving those signals to
  open official series (EIA, ECB, BoE, FRED public-domain series).
- **Charter**: a mobile app and a paid tier are listed as v1 non-goals, so the
  charter needs updating alongside this.
- **Name check**: other apps and companies already use "Canary". Check the App
  Store and trademarks before committing to the name.
- **App Store pack**: metadata, review notes, App Privacy and age-rating answers,
  subscription details and captioned screenshots are in `AppStore/` (see its
  README). Guideline 4.2 (minimum functionality) is the main review risk for an
  app that mirrors a website; the review notes set out the widgets, alerts, Siri,
  offline use and iPhone Duo layouts as the native value.
- **Alerts arrive late by design**: iOS decides when background refresh runs.
  Timely alerts would need a push server (APNs) — a later decision.

## Licence

The data is CC BY 4.0, attributed to Canary (canary.danleech.com) in Settings.
