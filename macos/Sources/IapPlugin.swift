import SwiftRs
import AppKit
import TauriSwiftRuntime
import WebKit
import StoreKit
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class DummyPlugin: Plugin {
    @objc func initialize(_ invoke: Invoke) {
        invoke.reject("Macos IAP plugin is not available due to swift concurrency limitations")
    }
    @objc func getProducts(_ invoke: Invoke) {
        invoke.reject("Macos IAP plugin is not available due to swift concurrency limitations")
    }
    @objc func purchase(_ invoke: Invoke) {
        invoke.reject("Macos IAP plugin is not available due to swift concurrency limitations")
    }
    @objc func restorePurchases(_ invoke: Invoke) {
        invoke.reject("Macos IAP plugin is not available due to swift concurrency limitations")
    }
    @objc func getPurchaseHistory(_ invoke: Invoke) {
        invoke.reject("Macos IAP plugin is not available due to swift concurrency limitations")
    }
    @objc func acknowledgePurchase(_ invoke: Invoke) {
        invoke.reject("Macos IAP plugin is not available due to swift concurrency limitations")
    }
}

@_cdecl("init_plugin_iap")
func initPlugin() -> Plugin {
    return DummyPlugin()
}
