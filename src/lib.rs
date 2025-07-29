use tauri::{
  plugin::{Builder, TauriPlugin},
  Manager, Runtime,
};

pub use models::*;

#[cfg(desktop)]
mod desktop;
#[cfg(mobile)]
mod mobile;

mod commands;
mod error;
mod models;

pub use error::{Error, Result};

#[cfg(desktop)]
use desktop::Iap;
#[cfg(mobile)]
use mobile::Iap;

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
    .invoke_handler(tauri::generate_handler![commands::ping])
    .setup(|app, api| {
      #[cfg(mobile)]
      let iap = mobile::init(app, api)?;
      #[cfg(desktop)]
      let iap = desktop::init(app, api)?;
      app.manage(iap);
      Ok(())
    })
    .build()
}
