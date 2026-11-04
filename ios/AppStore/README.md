# App Store pack

Everything App Store Connect asks for, ready to paste or upload. The text files
under `metadata/` follow fastlane's `deliver` layout, so either copy each one
into App Store Connect by hand or run
`fastlane deliver --metadata_path AppStore/metadata --screenshots_path <folder>`.

Nothing here contains personal details. The fields marked **Dan** need yours.

## Product page (`metadata/en-GB/`)

| Field | File | Limit | Notes |
|---|---|---|---|
| Name | `name.txt` | 30 | "Canary: Global Risk Signals". Do the name check first (see `ios/README.md`). |
| Subtitle | `subtitle.txt` | 30 | |
| Promotional text | `promotional_text.txt` | 170 | Can change without a new build. |
| Description | `description.txt` | 4,000 | Includes the subscription terms and the Terms of Use and Privacy links that Guideline 3.1.2 asks for. |
| Keywords | `keywords.txt` | 100 | Words already in the name and subtitle are left out, as Apple indexes those anyway. |
| What's New | `release_notes.txt` | 4,000 | |
| Support URL | `support_url.txt` | | GitHub issues. Apple wants a way to contact you; if you'd rather give an email or a contact page, change it. |
| Marketing URL | `marketing_url.txt` | | |
| Privacy Policy URL | `privacy_url.txt` | | Live at canary.danleech.com/privacy. |
| Category | `primary_category.txt`, `secondary_category.txt` | | News, then Reference. |
| Copyright | — | | **Dan**: "2026 <your name or company>". |

Locale is English (UK). Add English (US) only if you want US spelling there.

## Screenshots

The `appstore` job in `.github/workflows/ios.yml` makes them from each CI run's
simulator screenshots and uploads them as the `app-store-screenshots` artifact.
To make them locally: `python3 AppStore/make_screenshots.py <shots> <out> --fonts <dir with Inter TTFs>`.

| Folder | App Store Connect slot | Size | Status |
|---|---|---|---|
| `iphone-6.3` | iPhone, Dynamic Island, medium display | 1206 × 2622 | **Required** (at least one) |
| `iphone-6.9` | iPhone, Dynamic Island, large display | 1320 × 2868 | Optional; App Store Connect scales from it where needed |
| `duo-outer` | iPhone Duo, outer display | 1398 × 2034 | Required from April 2027 for iOS 27.1 SDK apps; earns the "optimised for iPhone Duo" badge |
| `duo-inner` | iPhone Duo, inner display | 2007 × 2853 | As above |
| `duo-inner-landscape` | iPhone Duo, inner display | 2853 × 2007 | As above; upload either orientation |

All are RGB PNGs with no alpha. Apple's forum says iPhone Duo upload in App
Store Connect arrives "later this year", so keep the Duo sets until the slot appears.

Captions describe what the app shows and never call a level a forecast or
advice. The board's text is live, so the screenshots show whatever was on the
board at the time of the CI run: rerun the workflow on a calmer day if you prefer.

## App Review (`metadata/review_information/notes.txt`)

The notes explain the AI-assessed levels, what the app adds to the website
(Guideline 4.2), how to reach the purchase screen, why alerts can arrive late,
and the withheld market figures. **Dan**: App Store Connect also asks for a
contact name, phone and email for the reviewer. No sign-in is needed.

## Canary+ subscriptions

Create one subscription group, "Canary+", with:

| Product ID | Duration | Display name (≤ 35) | Description (≤ 55) |
|---|---|---|---|
| `com.danleech.canary.plus.yearly` | 1 year | Canary+ Yearly | Alerts, unlimited pins and signal widgets |
| `com.danleech.canary.plus.monthly` | 1 month | Canary+ Monthly | Alerts, unlimited pins and signal widgets |

Prices in `Config/Canary.storekit` (£14.99 a year, £1.99 a month) are
placeholders. **Dan** decides the real ones. Each product needs a review
screenshot of the purchase screen: use `iphone-17-plus.png` from the
`shots-1` artifact.

## App Privacy

Answer **"No, we do not collect data from this app"**, which gives the label
**Data Not Collected**.

Why that holds:

- The app has no accounts, analytics, advertising or tracking SDKs.
- It only downloads public JSON from canary.danleech.com.
- Pins and settings stay on the device; purchases go through Apple.
- `Shared/PrivacyInfo.xcprivacy` already declares no tracking and no collected data, plus the UserDefaults reason.

Apple counts data as collected only if it leaves the device and is kept longer
than it takes to answer the request. If you turn on Cloudflare analytics or keep
request logs that include IP addresses, revisit the answer.

## Age rating (suggested answers)

Apple works the rating out from these answers; check each against the wording in
App Store Connect.

- **In-app controls** (parental controls, age assurance): none.
- **Capabilities**:
  - Unrestricted web access: **No**. Sources open in a Safari view on the cited page; there is no address bar or general browsing. If you'd rather not argue that point, a Yes moves the app to 16+.
  - User-generated content, messaging, advertising: **No**.
- **Medical or treatment information**: **None**. Health signals describe outbreaks and point to the WHO, NHS or UKHSA, but give no diagnosis or treatment advice.
- **Health or wellness topics**: None.
- **Violent themes**: the board reports wars, attacks and disasters in short, factual text, with no images or graphic detail. Answer **Infrequent** to the closest question about references to violence, and None to anything about depictions.
- **Everything else** (profanity, sexual content, drugs, alcohol, tobacco, gambling, contests, horror, loot boxes): **None**.

## Export compliance

`ITSAppUsesNonExemptEncryption` is already `NO` in `Config/Canary-Info.plist`:
the app uses only HTTPS through Apple's frameworks.

## Checklist before submitting

- [ ] Apple Developer Program membership and an App Store Connect record for `com.danleech.canary`
- [ ] Name check and trademark search
- [ ] Market-data licences (see `ios/README.md`), now that the app withholds those figures
- [ ] Charter updated for a mobile app and a paid tier
- [ ] Prices for Canary+
- [ ] Copyright, review contact, and a support contact you're happy to publish
- [ ] Controller name and contact on the privacy page (UK GDPR asks for both)
- [ ] Screenshots from a recent CI run
- [ ] A TestFlight build on a real iPhone: alerts, widgets, purchases and Siri can't be fully tested in the simulator
