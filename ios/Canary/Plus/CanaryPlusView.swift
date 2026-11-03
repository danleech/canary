import StoreKit
import SwiftUI

/// The Canary+ paywall, built on StoreKit's own subscription view so pricing,
/// trials, terms and purchase flow look and behave exactly as Apple's do.
struct CanaryPlusView: View {
    enum Reason {
        case general, pins, alerts, widgets
    }

    var reason: Reason = .general

    @Environment(\.dismiss) private var dismiss
    @Environment(PlusStore.self) private var plus

    var body: some View {
        SubscriptionStoreView(productIDs: PlusStore.productIDs) {
            PlusMarketing(reason: reason)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: AppConstants.privacyURL, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: AppConstants.termsURL, for: .termsOfService)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(_)) = result {
                await plus.refreshEntitlement()
                dismiss()
            }
        }
    }
}

private struct PlusMarketing: View {
    let reason: CanaryPlusView.Reason

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bird.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color.yellow.mix(with: .orange, by: 0.3).gradient, in: .rect(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Canary+")
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(PlusFeature.allCases, id: \.self) { feature in
                    Label {
                        Text(feature.title)
                    } icon: {
                        Image(systemName: feature.symbol)
                            .foregroundStyle(.tint)
                    }
                    .font(.body)
                }
                Label {
                    Text("The board itself stays free for everyone")
                } icon: {
                    Image(systemName: "globe")
                        .foregroundStyle(.tint)
                }
                .font(.body)
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var subtitle: LocalizedStringKey {
        switch reason {
        case .pins: "Pin more than \(PlusFeature.freePinLimit) signals, and get told when they change."
        case .alerts: "Get an alert when the signals you follow change level."
        case .widgets: "Keep the signals you follow on your Home Screen and Lock Screen."
        case .general: "Follow the signals that matter to you, wherever you are."
        }
    }
}
