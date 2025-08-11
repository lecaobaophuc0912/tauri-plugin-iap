# ⚠️ WARNING: WORK IS STILL IN PROGRESS. NOT READY FOR PRODUCTION YET

[![npm version](https://badge.fury.io/js/@choochmeque%2Ftauri-plugin-iap-api.svg)](https://badge.fury.io/js/@choochmeque%2Ftauri-plugin-iap-api)
![Crates.io Version](https://img.shields.io/crates/v/tauri-plugin-iap)


# Tauri Plugin IAP

A Tauri plugin for In-App Purchases (IAP) with support for subscriptions on both iOS (StoreKit 2) and Android (Google Play Billing).

## Features

- Initialize billing/store connection
- Query products and subscriptions with detailed pricing
- Purchase subscriptions with platform-specific features
- Restore previous purchases
- Get purchase history
- Real-time purchase state updates via events
- Automatic transaction verification (iOS)
- Support for introductory offers and free trials

## Platform Support

- **iOS**: StoreKit 2 (requires iOS 15.0+)
- **Android**: Google Play Billing Library v8.0.0

## Installation

Add the plugin to your Tauri project:

```toml
[dependencies]
tauri-plugin-iap = { path = "../path-to-plugin" }
```

Register the plugin in your Tauri app:

```rust
fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_iap::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

## Usage

### JavaScript/TypeScript

```typescript
import {
  initialize,
  getProducts,
  purchase,
  restorePurchases,
  acknowledgePurchase,
  onPurchaseUpdated
} from 'tauri-plugin-iap-api';

// Initialize the billing client
await initialize();

// Get available products
const products = await getProducts(['subscription_id_1', 'subscription_id_2'], 'subs');

// Purchase a subscription
// On Android: use the offer token from subscriptionOfferDetails
// On iOS: offer token is not used
const purchaseResult = await purchase('subscription_id_1', offerToken);

// Restore purchases
const restored = await restorePurchases();

// Acknowledge a purchase (Android only, iOS auto-acknowledges)
await acknowledgePurchase(purchaseResult.purchaseToken);

// Listen for purchase updates
const unlisten = onPurchaseUpdated((purchase) => {
  console.log('Purchase updated:', purchase);
});

// Stop listening
unlisten();
```

## Platform Setup

### iOS Setup

1. Configure your app in App Store Connect
2. Create subscription products with appropriate pricing
3. Add In-App Purchase capability to your app in Xcode:
   - Open your project in Xcode
   - Select your target
   - Go to "Signing & Capabilities"
   - Click "+" and add "In-App Purchase"
4. Test with sandbox accounts

### Android Setup

1. Add your app to Google Play Console
2. Create subscription products in Google Play Console
3. Configure your app's billing permissions (already included in the plugin)
4. Test with test accounts or sandbox environment

## API Reference

### `initialize()`
Initializes the billing client connection (required on Android, no-op on iOS).

### `getProducts(productIds: string[], productType: 'subs' | 'inapp')`
Fetches product details from the store.

**Returns:**
- `products`: Array of product objects with:
  - `productId`: Product identifier
  - `title`: Display name
  - `description`: Product description
  - `productType`: Type of product
  - `formattedPrice`: Localized price string
  - `subscriptionOfferDetails`: (subscriptions only) Array of offers

### `purchase(productId: string, offerToken?: string)`
Initiates a purchase flow.

**Parameters:**
- `productId`: The product to purchase
- `offerToken`: (Android only) The offer token for subscriptions

**Returns:** Purchase object with transaction details

### `restorePurchases()`
Queries and returns all active purchases.

### `getPurchaseHistory()`
Returns the complete purchase history.

### `acknowledgePurchase(purchaseToken: string)`
Acknowledges a purchase (required on Android within 3 days, no-op on iOS).

### `onPurchaseUpdated(callback: (purchase: Purchase) => void)`
Listens for purchase state changes.

## Differences Between Platforms

### iOS (StoreKit 2)
- Automatic transaction verification
- No manual acknowledgment needed
- Supports introductory offers and promotional offers
- Transaction updates are automatically observed
- Requires iOS 15.0+

### Android (Google Play Billing)
- Manual acknowledgment required within 3 days
- Supports multiple subscription offers per product
- Offer tokens required for subscription purchases
- More detailed pricing phase information

## Testing

### iOS
1. Use sandbox test accounts
2. Test on physical devices (subscriptions don't work well on simulators)
3. Clear purchase history in Settings > App Store > Sandbox Account

### Android
1. Upload your app to internal testing track
2. Add test accounts in Google Play Console
3. Test with test payment methods

## License

MIT or Apache-2.0
