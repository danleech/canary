# Canary for iPhone

A native SwiftUI app for the Canary board, designed to Apple's Human Interface
Guidelines and modelled on Health (Summary and Browse), Weather (the World State
hero and its gauge) and Stocks (pinned signals with sparklines and level pills).
It reads the same public, read-only API as the website, so the scheduled
assessment needs no changes to feed it.

## Requirements

- **Xcode 27.1 or later.** The iPhone Duo layouts use iOS 27.1 APIs
  (`reservedRegions`) and the iPhone Duo simulator needs the iOS 27.1 runtime.
- Deploys to **iOS 26.0 and later**, so it runs on every iPhone that runs iOS 26,
  from iPhone 11 / SE (2nd gen) onwards. iOS 27.1-only code is behind
  `#available` checks.

## Run it

1. Open `ios/Canary.xcodeproj`.
2. Choose the **Canary** scheme and any iPhone simulator, then press Run.
   No signing team is needed for the simulator.
3. To test Canary+ purchases in the simulator, nothing else is needed: the scheme
   uses `Config/Canary.storekit`, a local StoreKit configuration.
4. For a real device: select your team under *Signing & Capabilities* for both
   targets. Xcode registers the App Group `group.com.danleech.canary`
   automatically.

## What's in it

| Area | Files | Notes |
| --- | --- | --- |
| Summary tab | `Canary/Summary` | World State hero, Pinned, On Alert, Changed in the last 24 hours, Situations |
| Browse tab | `Canary/Browse` | Domains → signals. A split view at regular width |
| Changes tab | `Canary/Changes` | Status changes by day, filterable |
| Search tab | `Canary/Search` | Signals, domains, situations |
| Signal detail | `Canary/Detail` | Level, chart of recent checks (Swift Charts), why, what it means for you, how the level was set, thresholds, sources |
| Canary+ | `Canary/Plus`, `Canary/Stores/PlusStore.swift` | StoreKit 2, Apple's `SubscriptionStoreView` |
| Alerts | `Canary/Alerts` | Background app refresh + local notifications |
| Siri & Shortcuts | `Canary/Intents`, `Shared/Intents` | World State, check a signal, list alerts, open a signal |
| Widgets | `CanaryWidgets` | World State (free), Signal and Pinned (Canary+); Home Screen, Lock Screen, StandBy |
| Data layer | `Shared/Model`, `Shared/Networking` | Codable models of `api/v1/*.json` and `data/history.json`, offline cache in the App Group |

`Shared/` is compiled into both the app and the widget extension. The project
uses Xcode's synchronized folders, so new files are picked up automatically.

## Design rules followed

- **Standard containers only**: `TabView` with `Tab`, `NavigationStack`,
  `NavigationSplitView`, `List`, `Form`, toolbars, sheets and the system search
  tab. This is what lets iOS move the bars to the side on iPhone Duo and keep
  everything clear of the camera and the fold, as the HIG asks.
- **System typography and colours**: Dynamic Type text styles throughout, semantic
  colours, light and dark mode, accent colour only for interactive elements.
- **Colour is never the only cue** (charter §6): every level has its own symbol
  (octagon, triangle, circle, dashed circle) and its name in text. Badge colours
  meet WCAG AA contrast.
- **Accessibility**: VoiceOver labels for every row and card, an audio graph for
  charts, layouts that switch to stacked at accessibility text sizes.
- **Honesty**: the AI-assessment disclosure, basis (measured, published or AI
  judgement) and the not-advice disclaimer appear in the app as on the website.

## Every iPhone, including iPhone Duo

Layouts follow size classes, never device models or screen sizes.

| Display | Size classes | What the app does |
| --- | --- | --- |
| Any iPhone, portrait | compact width | One column, tab bar at the bottom |
| Pro Max / Plus, landscape | regular width | Two columns; Browse becomes a split view |
| iPhone Duo, closed (outer display) | compact width | One column; iOS moves bars into the vertical bar on the side |
| iPhone Duo, open (inner display) | regular × regular | Two columns, gutter on the hinge; Browse becomes a split view |
| iPhone Duo, half folded like a book | regular × regular | Same, with no card creased by the fold |

`Canary/Common/AdaptiveColumns.swift` does the reflow. On iOS 27.1 it reads the
display's vertical division region and puts the gutter on the hinge, because the
hinge is not in the middle of the safe area when the vertical bar takes one side.

Before submitting: from April 2027 App Store Connect needs iPhone Duo screenshots
(1398 × 2034 outer, 2007 × 2853 inner).

## Before the App Store

- **Apple Developer Program** membership (£79 / $99 a year) and an App Store
  Connect record with bundle ID `com.danleech.canary`.
- **Canary+ products**: two auto-renewable subscriptions in one group,
  `com.danleech.canary.plus.yearly` and `com.danleech.canary.plus.monthly`. The
  prices in `Canary.storekit` (£14.99 a year, £1.99 a month) are placeholders.
- **Privacy policy** at `https://canary.danleech.com/privacy`. The app collects
  nothing, but a subscription app needs a policy link. `PrivacyInfo.xcprivacy`
  declares no tracking and no collected data.
- **App Review notes**: explain that statuses are AI-assessed against published
  rubrics, and point to the methodology page. Guideline 4.2 (minimum
  functionality) is the main risk for an app that mirrors a website; the widgets,
  alerts, Siri and offline use are the native value.
- **Alerts arrive late by design**: iOS decides when background refresh runs.
  Timely alerts would need a push server (APNs) — a later decision.

## Licence

The data is CC BY 4.0, attributed to Canary (canary.danleech.com) in Settings.
