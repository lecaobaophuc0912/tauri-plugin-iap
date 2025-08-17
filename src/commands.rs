use tauri::{AppHandle, command, Runtime};

use crate::models::*;
use crate::{IapExt, Result};

#[command]
pub(crate) async fn initialize<R: Runtime>(
    app: AppHandle<R>,
) -> Result<InitializeResponse> {
    app.iap().initialize()
}

#[command]
pub(crate) async fn get_products<R: Runtime>(
    app: AppHandle<R>,
    payload: GetProductsRequest,
) -> Result<GetProductsResponse> {
    app.iap().get_products(payload.product_ids, payload.product_type)
}

#[command]
pub(crate) async fn purchase<R: Runtime>(
    app: AppHandle<R>,
    payload: PurchaseRequest,
) -> Result<Purchase> {
    app.iap().purchase(payload.product_id, payload.product_type, payload.offer_token)
}

#[command]
pub(crate) async fn restore_purchases<R: Runtime>(
    app: AppHandle<R>,
    payload: RestorePurchasesRequest,
) -> Result<RestorePurchasesResponse> {
    app.iap().restore_purchases(payload.product_type)
}

#[command]
pub(crate) async fn get_purchase_history<R: Runtime>(
    app: AppHandle<R>,
) -> Result<GetPurchaseHistoryResponse> {
    app.iap().get_purchase_history()
}

#[command]
pub(crate) async fn acknowledge_purchase<R: Runtime>(
    app: AppHandle<R>,
    payload: AcknowledgePurchaseRequest,
) -> Result<AcknowledgePurchaseResponse> {
    app.iap().acknowledge_purchase(payload.purchase_token)
}