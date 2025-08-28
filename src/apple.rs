use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};
use tauri_swift_runtime::{PluginApiExt, PluginHandleExt};

use crate::models::*;

tauri_swift_runtime::swift_plugin_binding!(init_plugin_iap);

pub fn init<R: Runtime, C: DeserializeOwned>(
  _app: &AppHandle<R>,
  api: PluginApi<R, C>,
) -> crate::Result<Iap<R>> {
  let api: PluginApiExt<_, _> = api.into();
  let handle = api.register_swift_plugin(init_plugin_iap)?;
  Ok(Iap(handle))
}

/// Access to the iap APIs.
pub struct Iap<R: Runtime>(PluginHandleExt<R>);

impl<R: Runtime> Iap<R> {
  pub fn initialize(&self) -> crate::Result<InitializeResponse> {
    self
      .0
      .run_swift_plugin("initialize", InitializeRequest {})
      .map_err(Into::into)
  }

  pub fn get_products(&self, product_ids: Vec<String>, product_type: String) -> crate::Result<GetProductsResponse> {
    self.0
      .run_swift_plugin("getProducts", GetProductsRequest { product_ids, product_type })
      .map_err(Into::into)
  }

  pub fn purchase(&self, product_id: String, product_type: String, offer_token: Option<String>) -> crate::Result<Purchase> {
    self.0
      .run_swift_plugin("purchase", PurchaseRequest { product_id, product_type, offer_token })
      .map_err(Into::into)
  }

  pub fn restore_purchases(&self, product_type: String) -> crate::Result<RestorePurchasesResponse> {
    self.0
      .run_swift_plugin("restorePurchases", RestorePurchasesRequest { product_type })
      .map_err(Into::into)
  }

  pub fn get_purchase_history(&self) -> crate::Result<GetPurchaseHistoryResponse> {
    self.0
      .run_swift_plugin("getPurchaseHistory", ())
      .map_err(Into::into)
  }

  pub fn acknowledge_purchase(&self, purchase_token: String) -> crate::Result<AcknowledgePurchaseResponse> {
    self.0
      .run_swift_plugin("acknowledgePurchase", AcknowledgePurchaseRequest { purchase_token })
      .map_err(Into::into)
  }

  pub fn get_product_status(&self, product_id: String, product_type: String) -> crate::Result<ProductStatus> {
    self.0
      .run_swift_plugin("getProductStatus", GetProductStatusRequest { product_id, product_type })
      .map_err(Into::into)
  }
}