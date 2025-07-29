use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};

use crate::models::*;

pub fn init<R: Runtime, C: DeserializeOwned>(
  app: &AppHandle<R>,
  _api: PluginApi<R, C>,
) -> crate::Result<Iap<R>> {
  Ok(Iap(app.clone()))
}

/// Access to the iap APIs.
pub struct Iap<R: Runtime>(AppHandle<R>);

impl<R: Runtime> Iap<R> {
  pub fn initialize(&self) -> crate::Result<InitializeResponse> {
    Err(crate::Error::from("IAP is not supported on desktop platforms"))
  }

  pub fn get_products(&self, _product_ids: Vec<String>, _product_type: String) -> crate::Result<GetProductsResponse> {
    Err(crate::Error::from("IAP is not supported on desktop platforms"))
  }

  pub fn purchase(&self, _product_id: String, _offer_token: Option<String>) -> crate::Result<Purchase> {
    Err(crate::Error::from("IAP is not supported on desktop platforms"))
  }

  pub fn restore_purchases(&self) -> crate::Result<RestorePurchasesResponse> {
    Err(crate::Error::from("IAP is not supported on desktop platforms"))
  }

  pub fn get_purchase_history(&self) -> crate::Result<GetPurchaseHistoryResponse> {
    Err(crate::Error::from("IAP is not supported on desktop platforms"))
  }

  pub fn acknowledge_purchase(&self, _purchase_token: String) -> crate::Result<AcknowledgePurchaseResponse> {
    Err(crate::Error::from("IAP is not supported on desktop platforms"))
  }
}