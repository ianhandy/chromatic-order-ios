//  Device-shake detection for SwiftUI. UIWindow's motionEnded fires on
//  a shake gesture; forward that through NotificationCenter so any
//  View can react via .onShake { ... }.

import SwiftUI
import UIKit

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("KromaDeviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

private struct ShakeViewModifier: ViewModifier {
    let onShake: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)
        ) { _ in onShake() }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeViewModifier(onShake: action))
    }
}
