const COMMANDS: &[&str] = &["initialize", "get_products", "purchase", "restore_purchases", "get_purchase_history", "acknowledge_purchase"];

fn main() {
  tauri_plugin::Builder::new(COMMANDS)
    .android_path("android")
    .ios_path("ios")
    .build();
}
