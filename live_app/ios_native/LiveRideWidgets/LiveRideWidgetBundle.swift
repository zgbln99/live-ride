import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// The extension deploys to iOS 16.2, which is where the ActivityKit API this
/// widget uses settled, so nothing here needs an availability guard.
@main
struct LiveRideWidgetBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}
