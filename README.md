# ⚠️ WARNING: WORK IS STILL IN PROGRESS. NOT READY FOR PRODUCTION YET

![NPM Version](https://img.shields.io/npm/v/@choochmeque%2Ftauri-plugin-iap-api)
![Crates.io Version](https://img.shields.io/crates/v/tauri-plugin-iap)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)


# Tauri Plugin IAP

A Tauri plugin for In-App Purchases (IAP) with support for subscriptions on both iOS (StoreKit 2) and Android (Google Play Billing).

## Features

- Initialize billing/store connection
- Query products and subscriptions with detailed pricing
- Purchase subscriptions with platform-specific features
- Restore previous purchases
- Get purchase history
- Check product ownership and subscription status
- Real-time purchase state updates via events
- Automatic transaction verification (iOS)
- Support for introductory offers and free trials

## Platform Support

- **iOS**: StoreKit 2 (requires iOS 15.0+)
- **Android**: Google Play Billing Library v8.0.0

## Installation

Install the JavaScript package:

```bash
npm install @choochmeque/tauri-plugin-iap-api
# or
yarn add @choochmeque/tauri-plugin-iap-api
# or
pnpm add @choochmeque/tauri-plugin-iap-api
```

Add the plugin to your Tauri project's `Cargo.toml`:

```toml
[dependencies]
tauri-plugin-iap = "0.1"
```

Configure the plugin permissions in your `capabilities/default.json`:

```json
{
  "permissions": [
    "iap:default"
  ]
}
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
  getProductStatus,
  onPurchaseUpdated,
  PurchaseState
} from 'tauri-plugin-iap-api';

// Initialize the billing client
await initialize();

// Get available products
const products = await getProducts(['subscription_id_1', 'subscription_id_2'], 'subs');

// Check if user owns a specific product
const status = await getProductStatus('subscription_id_1', 'subs');
if (status.isOwned && status.purchaseState === PurchaseState.PURCHASED) {
  console.log('User has active subscription');
  if (status.isAutoRenewing) {
    console.log('Subscription will auto-renew');
  }
}

// Purchase a subscription or in-app product
// On Android: use the offer token from subscriptionOfferDetails
// On iOS: offer token is not used
const purchaseResult = await purchase('subscription_id_1', 'subs', offerToken);

// Restore purchases (specify product type)
const restored = await restorePurchases('subs');

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

### `purchase(productId: string, productType: 'subs' | 'inapp' = 'subs', offerToken?: string)`
Initiates a purchase flow.

**Parameters:**
- `productId`: The product to purchase
- `productType`: Type of product ('subs' for subscriptions, 'inapp' for one-time purchases), defaults to 'subs'
- `offerToken`: (Android only) The offer token for subscriptions

**Returns:** Purchase object with transaction details

### `restorePurchases(productType: 'subs' | 'inapp' = 'subs')`
Queries and returns all active purchases.

**Parameters:**
- `productType`: Type of products to restore ('subs' or 'inapp'), defaults to 'subs'

### `getPurchaseHistory()`
Returns the complete purchase history.

### `acknowledgePurchase(purchaseToken: string)`
Acknowledges a purchase (required on Android within 3 days, no-op on iOS).

### `getProductStatus(productId: string, productType: 'subs' | 'inapp' = 'subs')`
Checks the ownership and subscription status of a specific product.

**Parameters:**
- `productId`: The product identifier to check
- `productType`: Type of product ('subs' or 'inapp'), defaults to 'subs'

**Returns:** ProductStatus object with:
- `productId`: Product identifier
- `isOwned`: Whether the user currently owns the product
- `purchaseState`: Current state (PURCHASED=0, CANCELED=1, PENDING=2)
- `purchaseTime`: When the product was purchased (timestamp)
- `expirationTime`: (subscriptions only) When the subscription expires
- `isAutoRenewing`: (subscriptions only) Whether auto-renewal is enabled
- `isAcknowledged`: Whether the purchase has been acknowledged
- `purchaseToken`: Token for the purchase transaction

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

[MIT](LICENSE)
