use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeRequest {}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {
    pub success: bool,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetProductsRequest {
    pub product_ids: Vec<String>,
    #[serde(default = "default_product_type")]
    pub product_type: String,
}

fn default_product_type() -> String {
    "subs".to_string()
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PricingPhase {
    pub formatted_price: String,
    pub price_currency_code: String,
    pub price_amount_micros: i64,
    pub billing_period: String,
    pub billing_cycle_count: i32,
    pub recurrence_mode: i32,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionOffer {
    pub offer_token: String,
    pub base_plan_id: String,
    pub offer_id: Option<String>,
    pub pricing_phases: Vec<PricingPhase>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Product {
    pub product_id: String,
    pub title: String,
    pub description: String,
    pub product_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub formatted_price: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub price_currency_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub price_amount_micros: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subscription_offer_details: Option<Vec<SubscriptionOffer>>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetProductsResponse {
    pub products: Vec<Product>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PurchaseRequest {
    pub product_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offer_token: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Purchase {
    pub order_id: Option<String>,
    pub package_name: String,
    pub product_id: String,
    pub purchase_time: i64,
    pub purchase_token: String,
    pub purchase_state: i32,
    pub is_auto_renewing: bool,
    pub is_acknowledged: bool,
    pub original_json: String,
    pub signature: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RestorePurchasesResponse {
    pub purchases: Vec<Purchase>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PurchaseHistoryRecord {
    pub product_id: String,
    pub purchase_time: i64,
    pub purchase_token: String,
    pub quantity: i32,
    pub original_json: String,
    pub signature: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetPurchaseHistoryResponse {
    pub history: Vec<PurchaseHistoryRecord>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AcknowledgePurchaseRequest {
    pub purchase_token: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AcknowledgePurchaseResponse {
    pub success: bool,
}