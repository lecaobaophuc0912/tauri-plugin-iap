use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};

use crate::models::*;

#[swift_bridge::bridge]
mod ffi {
    pub enum FFIResult {
        Ok(String), // json string from Swift
        Err(String), // error message from Swift
    }

    extern "Swift" {
        fn initialize() -> FFIResult;
        fn getProducts(productIds: Vec<String>, productType: String) -> FFIResult;
        fn purchase(
            productId: String,
            productType: String,
            offerToken: Option<String>,
        ) -> FFIResult;
        fn restorePurchases(productType: String) -> FFIResult;
        fn acknowledgePurchase(purchaseToken: String) -> FFIResult;
        fn getProductStatus(productId: String, productType: String) -> FFIResult;
    }
}

pub fn init<R: Runtime, C: DeserializeOwned>(
    app: &AppHandle<R>,
    _api: PluginApi<R, C>,
) -> crate::Result<Iap<R>> {
    Ok(Iap(app.clone()))
}

/// Access to the iap APIs.
pub struct Iap<R: Runtime>(AppHandle<R>);

impl<R: Runtime> Iap<R> {
    /// Convert the bridged FFI result to a Rust Result.
    fn to_result<T: serde::de::DeserializeOwned>(bridged: ffi::FFIResult) -> crate::Result<T> {
        match bridged {
            ffi::FFIResult::Ok(response) => {
                let parsed: T = serde_json::from_str(&response).map_err(Into::<serde_json::Error>::into)?;
                Ok(parsed)
            }
            ffi::FFIResult::Err(err) => Err(std::io::Error::new(std::io::ErrorKind::Other, err).into()),
        }
    }

    pub fn initialize(&self) -> crate::Result<InitializeResponse> {
        Self::to_result(ffi::initialize())
    }

    pub fn get_products(
        &self,
        product_ids: Vec<String>,
        product_type: String,
    ) -> crate::Result<GetProductsResponse> {
        Self::to_result(ffi::getProducts(product_ids, product_type))
    }

    pub fn purchase(
        &self,
        product_id: String,
        product_type: String,
        offer_token: Option<String>,
    ) -> crate::Result<Purchase> {
        Self::to_result(ffi::purchase(product_id, product_type, offer_token))
    }

    pub fn restore_purchases(
        &self,
        product_type: String,
    ) -> crate::Result<RestorePurchasesResponse> {
        Self::to_result(ffi::restorePurchases(product_type))
    }

    pub fn acknowledge_purchase(
        &self,
        purchase_token: String,
    ) -> crate::Result<AcknowledgePurchaseResponse> {
        Self::to_result(ffi::acknowledgePurchase(purchase_token))
    }

    pub fn get_product_status(
        &self,
        product_id: String,
        product_type: String,
    ) -> crate::Result<ProductStatus> {
        Self::to_result(ffi::getProductStatus(product_id, product_type))
    }
}
