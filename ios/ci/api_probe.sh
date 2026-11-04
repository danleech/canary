#!/bin/bash
# Prints the declarations, with availability, of SwiftUI APIs the app relies on,
# straight from the selected SDK's Swift interfaces. Read-only.
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "SDK: $SDK"
IFACES=$(ls "$SDK"/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-ios-simulator.swiftinterface \
  "$SDK"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface 2>/dev/null)
probe() {
  echo "=== $1"
  # shellcheck disable=SC2086
  grep -h -B2 -A1 -E "$1" $IFACES | grep -v "^--$" | cut -c1-240 | head -${2:-14}
}
probe "func defaultTabBarPlacement"
probe "struct AdaptableTabBarPlacement" 4
probe "static var (sidebar|tabBar|automatic): SwiftUI.AdaptableTabBarPlacement" 8
probe "func defaultVisibility\(" 10
probe "struct TabPlacement" 4
probe "static var (sidebarOnly|pinned): SwiftUI.TabPlacement" 6
probe "func tabPlacement" 6
probe "sidebarAdaptable" 6
probe "func tabViewSidebarHeader" 6
probe "func tabBarMinimizeBehavior" 6
probe "static var (close|confirm): SwiftUI.ButtonRole" 8
probe "init\(role: SwiftUI.ButtonRole\?, action:" 6
probe "func reservedRegions" 6
probe "func navigationSubtitle" 6
probe "func scrollEdgeEffectStyle" 6
probe "func backgroundExtensionEffect" 4
probe "func toolbarTitleDisplayMode" 4
probe "func sectionIndexLabel" 4
probe "func sharedBackgroundVisibility" 6
probe "func onScrollGeometryChange" 6
