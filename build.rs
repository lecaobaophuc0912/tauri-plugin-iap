const COMMANDS: &[&str] = &["initialize", "get_products", "purchase", "restore_purchases", "get_purchase_history", "acknowledge_purchase"];

fn main() {
  tauri_plugin::Builder::new(COMMANDS)
    .android_path("android")
    .ios_path("ios")
    .build();

  if std::env::var("CARGO_CFG_TARGET_OS").unwrap().as_str() == "macos" {
    // swift-rs has a minimum of macOS 10.13
    // Ensure the same minimum supported macOS version is specified as in your `Package.swift` file.
    #[cfg(target_os = "macos")]
    swift_rs::SwiftLinker::new("10.15")
        .with_package("tauri-plugin-iap", "./macos/")
        .link();
  }
}
