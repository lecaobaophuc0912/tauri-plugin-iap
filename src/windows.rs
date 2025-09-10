use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};
use windows::core::HSTRING;
use windows::Foundation::DateTime;
use windows::Services::Store::{
    StoreContext, StoreLicense, StoreProduct, StorePurchaseProperties, StorePurchaseStatus,
};
use windows_collections::IIterable;

use crate::models::*;
use std::sync::{Arc, RwLock};

pub fn init<R: Runtime, C: DeserializeOwned>(
    app: &AppHandle<R>,
    _api: PluginApi<R, C>,
) -> crate::Result<Iap<R>> {
    Ok(Iap {
        app_handle: app.clone(),
        store_context: Arc::new(RwLock::new(None)),
    })
}

/// Access to the iap APIs.
pub struct Iap<R: Runtime> {
    app_handle: AppHandle<R>,
    store_context: Arc<RwLock<Option<StoreContext>>>,
}

impl<R: Runtime> Iap<R> {
    /// Get or create the StoreContext instance
    fn get_store_context(&self) -> crate::Result<StoreContext> {
        let mut context_guard = self.store_context.write().unwrap();

        if context_guard.is_none() {
            // Get the default store context for the current user
            let context = StoreContext::GetDefault().map_err(|e| {
                std::io::Error::other(format!("Failed to get store context: {:?}", e))
            })?;

            *context_guard = Some(context);
        }

        Ok(context_guard.as_ref().unwrap().clone())
    }

    /// Convert Windows DateTime to Unix timestamp in milliseconds
    fn datetime_to_unix_millis(datetime: &DateTime) -> i64 {
        // Windows DateTime is in 100-nanosecond intervals since January 1, 1601
        // Convert to Unix timestamp (milliseconds since January 1, 1970)
        const WINDOWS_TICK: i64 = 10000000;
        const SEC_TO_UNIX_EPOCH: i64 = 11644473600;

        let windows_ticks = datetime.UniversalTime;
        let seconds_since_1601 = windows_ticks / WINDOWS_TICK;
        let unix_seconds = seconds_since_1601 - SEC_TO_UNIX_EPOCH;
        unix_seconds * 1000 // Convert to milliseconds
    }

    pub fn initialize(&self) -> crate::Result<InitializeResponse> {
        let _ = self.get_store_context()?;
        Ok(InitializeResponse { success: true })
    }

    pub fn get_products(
        &self,
        product_ids: Vec<String>,
        product_type: String,
    ) -> crate::Result<GetProductsResponse> {
        let context = self.get_store_context()?;

        // Convert product IDs to HSTRING
        let store_ids: Vec<HSTRING> = product_ids
            .iter()
            .map(|id| HSTRING::from(id.as_str()))
            .collect();

        // Determine product kinds based on type
        let product_kinds: Vec<HSTRING> = match product_type.as_str() {
            "inapp" => vec![
                HSTRING::from("Consumable"),
                HSTRING::from("UnmanagedConsumable"),
                HSTRING::from("Durable"),
            ],
            "subs" => vec![HSTRING::from("Subscription")],
            _ => vec![
                HSTRING::from("Consumable"),
                HSTRING::from("UnmanagedConsumable"),
                HSTRING::from("Durable"),
                HSTRING::from("Subscription"),
            ],
        };

        let kinds_it: IIterable<HSTRING> = IIterable::try_from(product_kinds)
            .map_err(|e| std::io::Error::other(format!("Failed to create IIterable: {:?}", e)))?;
        let ids_it: IIterable<HSTRING> = IIterable::try_from(store_ids)
            .map_err(|e| std::io::Error::other(format!("Failed to create IIterable: {:?}", e)))?;

        // Query products from the store
        let query_result = context
            .GetStoreProductsAsync(&kinds_it, &ids_it)
            .and_then(|async_op| async_op.get())
            .map_err(|e| std::io::Error::other(format!("Failed to get products: {:?}", e)))?;

        // Check for any errors
        let extended_error = query_result.ExtendedError()?;
        if extended_error.is_err() {
            return Err(std::io::Error::other(format!(
                "Store query failed with error: {:?}",
                extended_error.message()
            ))
            .into());
        }

        let products_map = query_result.Products()?;
        let mut products = Vec::new();

        // Iterate through the products
        let iterator = products_map.First()?;
        while iterator.HasCurrent()? {
            let item = iterator.Current()?;
            let store_product = item.Value()?;

            let product = self.convert_store_product_to_product(&store_product, &product_type)?;
            products.push(product);

            iterator.MoveNext()?;
        }

        Ok(GetProductsResponse { products })
    }

    fn convert_store_product_to_product(
        &self,
        store_product: &StoreProduct,
        product_type: &str,
    ) -> crate::Result<Product> {
        let product_id = store_product.StoreId()?.to_string();

        let title = store_product.Title()?.to_string();

        let description = store_product.Description()?.to_string();

        let price = store_product.Price()?;

        let formatted_price = price.FormattedPrice()?.to_string();

        let currency_code = price.CurrencyCode()?.to_string();

        // Get the raw price value
        let formatted_base_price = price.FormattedBasePrice()?.to_string();

        // Parse price to get numeric value (remove currency symbols)
        let price_value = formatted_base_price
            .chars()
            .filter(|c| c.is_numeric() || *c == '.')
            .collect::<String>()
            .parse::<f64>()
            .unwrap_or(0.0);

        let price_amount_micros = (price_value * 1_000_000.0) as i64;

        // Handle subscription offers if this is a subscription product
        let subscription_offer_details = if product_type == "subs" {
            let mut offers = Vec::new();

            // Get SKUs for subscription details
            let skus = store_product.Skus()?;
            let sku_count = skus.Size()?;

            for i in 0..sku_count {
                let sku = skus.GetAt(i)?;

                let sku_id = sku.StoreId()?.to_string();
                sku.StoreId()?.to_string();

                let sku_price = sku.Price()?;

                // Check if this SKU has subscription info
                let subscription_info = sku.SubscriptionInfo();

                if let Ok(info) = subscription_info {
                    let billing_period = info.BillingPeriod()?;
                    let billing_period_unit = info.BillingPeriodUnit()?;

                    let billing_period_str = format!(
                        "P{}{}",
                        billing_period,
                        match billing_period_unit.0 {
                            0 => "D", // Day
                            1 => "W", // Week
                            2 => "M", // Month
                            3 => "Y", // Year
                            _ => "M",
                        }
                    );

                    let pricing_phase = PricingPhase {
                        formatted_price: sku_price.FormattedPrice()?.to_string(),
                        price_currency_code: currency_code.clone(),
                        price_amount_micros,
                        billing_period: billing_period_str,
                        billing_cycle_count: 0, // Windows doesn't provide this directly
                        recurrence_mode: 1,     // Infinite recurring
                    };

                    let offer = SubscriptionOffer {
                        offer_token: sku_id.clone(),
                        base_plan_id: sku_id,
                        offer_id: None,
                        pricing_phases: vec![pricing_phase],
                    };

                    offers.push(offer);
                }
            }

            if !offers.is_empty() {
                Some(offers)
            } else {
                None
            }
        } else {
            None
        };

        Ok(Product {
            product_id,
            title,
            description,
            product_type: product_type.to_string(),
            formatted_price: Some(formatted_price),
            price_currency_code: Some(currency_code),
            price_amount_micros: Some(price_amount_micros),
            subscription_offer_details,
        })
    }

    pub fn purchase(
        &self,
        product_id: String,
        product_type: String,
        options: Option<PurchaseOptions>,
    ) -> crate::Result<Purchase> {
        let context = self.get_store_context()?;

        // Get the product first to ensure it exists
        let products_response =
            self.get_products(vec![product_id.clone()], product_type.clone())?;

        if products_response.products.is_empty() {
            return Err(std::io::Error::other("Product not found").into());
        }

        let store_id = HSTRING::from(&product_id);

        // Create purchase properties if we have an offer token (for subscriptions)
        let offer_token = options.and_then(|opts| opts.offer_token);
        let purchase_result = if let Some(token) = offer_token {
            let properties = StorePurchaseProperties::Create(&HSTRING::from(&product_id))?;

            // Set the SKU ID for subscription offers
            properties
                .SetExtendedJsonData(&HSTRING::from(format!(r#"{{"skuId":"{}"}}"#, token)))?;

            context
                .RequestPurchaseWithPurchasePropertiesAsync(&store_id, &properties)
                .and_then(|async_op| async_op.get())
                .map_err(|e| std::io::Error::other(format!("Purchase request failed: {:?}", e)))?
        } else {
            // Simple purchase without properties
            context
                .RequestPurchaseAsync(&store_id)
                .and_then(|async_op| async_op.get())
                .map_err(|e| std::io::Error::other(format!("Purchase request failed: {:?}", e)))?
        };

        // Check purchase status
        let status = purchase_result.Status()?;

        let purchase_state = match status {
            StorePurchaseStatus::Succeeded => PurchaseStateValue::Purchased as i32,
            StorePurchaseStatus::AlreadyPurchased => PurchaseStateValue::Purchased as i32,
            StorePurchaseStatus::NotPurchased => PurchaseStateValue::Canceled as i32,
            StorePurchaseStatus::NetworkError => {
                return Err(std::io::Error::other("Network error during purchase").into());
            }
            StorePurchaseStatus::ServerError => {
                return Err(std::io::Error::other("Server error during purchase").into());
            }
            _ => return Err(std::io::Error::other("Purchase failed").into()),
        };

        // Get extended error info if available
        let extended_error = purchase_result.ExtendedError().ok();
        let error_message = if let Some(error) = extended_error {
            error.message()
        } else {
            String::new()
        };

        // Generate purchase details
        let purchase_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;

        let purchase_token = format!("win_{}_{}", product_id, purchase_time);

        Ok(Purchase {
            order_id: Some(purchase_token.clone()),
            package_name: self.app_handle.package_info().name.clone(),
            product_id: product_id.clone(),
            purchase_time,
            purchase_token: purchase_token.clone(),
            purchase_state,
            is_auto_renewing: product_type == "subs",
            is_acknowledged: true, // Windows Store handles acknowledgment
            original_json: format!(
                r#"{{"status":{},"message":"{}","productId":"{}"}}"#,
                status.0, error_message, product_id
            ),
            signature: String::new(), // Windows doesn't provide signatures like Android
        })
    }

    pub fn restore_purchases(
        &self,
        product_type: String,
    ) -> crate::Result<RestorePurchasesResponse> {
        let context = self.get_store_context()?;

        // Get app license info
        let app_license = context
            .GetAppLicenseAsync()
            .and_then(|async_op| async_op.get())
            .map_err(|e| std::io::Error::other(format!("Failed to get app license: {:?}", e)))?;

        let mut purchases = Vec::new();

        // Get add-on licenses (in-app purchases)
        let addon_licenses = app_license.AddOnLicenses()?;

        let iterator = addon_licenses.First()?;
        while iterator.HasCurrent()? {
            let item = iterator.Current()?;
            let license = item.Value()?;

            let purchase = self.convert_license_to_purchase(&license, &product_type)?;

            if purchase.purchase_state == PurchaseStateValue::Purchased as i32 {
                purchases.push(purchase);
            }

            iterator.MoveNext()?;
        }

        Ok(RestorePurchasesResponse { purchases })
    }

    fn convert_license_to_purchase(
        &self,
        license: &StoreLicense,
        product_type: &str,
    ) -> crate::Result<Purchase> {
        let product_id = license.InAppOfferToken()?.to_string();

        let sku_store_id = license.SkuStoreId()?.to_string();

        let is_active = license.IsActive()?;

        let expiration_date = license.ExpirationDate()?;
        let expiration_millis = Self::datetime_to_unix_millis(&expiration_date);

        // Estimate purchase time (30 days before expiration for monthly subs)
        let purchase_time = if product_type == "subs" && expiration_millis > 0 {
            expiration_millis - (30 * 24 * 60 * 60 * 1000)
        } else {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as i64
        };

        let purchase_state = if is_active {
            PurchaseStateValue::Purchased as i32
        } else {
            PurchaseStateValue::Canceled as i32
        };

        Ok(Purchase {
            order_id: Some(sku_store_id.clone()),
            package_name: self.app_handle.package_info().name.clone(),
            product_id,
            purchase_time,
            purchase_token: sku_store_id,
            purchase_state,
            is_auto_renewing: product_type == "subs" && is_active,
            is_acknowledged: true,
            original_json: format!(
                r#"{{"isActive":{},"expirationDate":{}}}"#,
                is_active, expiration_millis
            ),
            signature: String::new(),
        })
    }

    pub fn acknowledge_purchase(
        &self,
        _purchase_token: String,
    ) -> crate::Result<AcknowledgePurchaseResponse> {
        // Windows Store handles acknowledgment automatically
        // This method exists for API compatibility
        Ok(AcknowledgePurchaseResponse { success: true })
    }

    pub fn get_product_status(
        &self,
        product_id: String,
        product_type: String,
    ) -> crate::Result<ProductStatus> {
        let context = self.get_store_context()?;

        // Get app license to check ownership
        let app_license = context
            .GetAppLicenseAsync()
            .and_then(|async_op| async_op.get())
            .map_err(|e| std::io::Error::other(format!("Failed to get app license: {:?}", e)))?;

        let addon_licenses = app_license.AddOnLicenses()?;

        // Look for the specific product license
        let product_key = HSTRING::from(&product_id);
        let has_license = addon_licenses.HasKey(&product_key)?;

        if has_license {
            let license = addon_licenses.Lookup(&product_key)?;

            let is_active = license.IsActive()?;
            let expiration_date = license.ExpirationDate()?;
            let expiration_time = Self::datetime_to_unix_millis(&expiration_date);

            let purchase_time = if product_type == "subs" && expiration_time > 0 {
                expiration_time - (30 * 24 * 60 * 60 * 1000)
            } else {
                expiration_time
            };

            let purchase_state = if is_active {
                Some(PurchaseStateValue::Purchased)
            } else {
                Some(PurchaseStateValue::Canceled)
            };

            let sku_store_id = license.SkuStoreId()?.to_string();

            Ok(ProductStatus {
                product_id,
                is_owned: is_active,
                purchase_state,
                purchase_time: Some(purchase_time),
                expiration_time: if expiration_time > 0 {
                    Some(expiration_time)
                } else {
                    None
                },
                is_auto_renewing: Some(product_type == "subs" && is_active),
                is_acknowledged: Some(true),
                purchase_token: Some(sku_store_id),
            })
        } else {
            Ok(ProductStatus {
                product_id,
                is_owned: false,
                purchase_state: None,
                purchase_time: None,
                expiration_time: None,
                is_auto_renewing: None,
                is_acknowledged: None,
                purchase_token: None,
            })
        }
    }
}
