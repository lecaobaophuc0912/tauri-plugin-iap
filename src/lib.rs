use tauri::{
  plugin::{Builder, TauriPlugin},
  Manager, Runtime,
};

pub use models::*;

#[cfg(target_os = "android")]
mod android;
#[cfg(any(target_os = "macos", target_os = "ios"))]
mod apple;
#[cfg(any(target_os = "windows", target_os = "linux"))]
mod desktop;

mod commands;
mod error;
mod models;

pub use error::{Error, Result};

#[cfg(target_os = "android")]
use android::Iap;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use apple::Iap;
#[cfg(any(target_os = "windows", target_os = "linux"))]
use desktop::Iap;

/// Extensions to [`tauri::App`], [`tauri::AppHandle`] and [`tauri::Window`] to access the iap APIs.
pub trait IapExt<R: Runtime> {
  fn iap(&self) -> &Iap<R>;
}

impl<R: Runtime, T: Manager<R>> crate::IapExt<R> for T {
  fn iap(&self) -> &Iap<R> {
    self.state::<Iap<R>>().inner()
  }
}

/// Initializes the plugin.
pub fn init<R: Runtime>() -> TauriPlugin<R> {
  Builder::new("iap")
    .invoke_handler(tauri::generate_handler![
      commands::initialize,
      commands::get_products,
      commands::purchase,
      commands::restore_purchases,
      commands::get_purchase_history,
      commands::acknowledge_purchase,
      commands::get_product_status,
    ])
    .setup(|app, api| {
      #[cfg(target_os = "android")]
      let iap = android::init(app, api)?;
      #[cfg(any(target_os = "macos", target_os = "ios"))]
      let iap = apple::init(app, api)?;
      #[cfg(any(target_os = "windows", target_os = "linux"))]
      let iap = desktop::init(app, api)?;
      app.manage(iap);
      Ok(())
    })
    .build()
}
