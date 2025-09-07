import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export interface InitializeResponse {
  success: boolean;
}

export interface PricingPhase {
  formattedPrice: string;
  priceCurrencyCode: string;
  priceAmountMicros: number;
  billingPeriod: string;
  billingCycleCount: number;
  recurrenceMode: number;
}

export interface SubscriptionOffer {
  offerToken: string;
  basePlanId: string;
  offerId?: string;
  pricingPhases: PricingPhase[];
}

export interface Product {
  productId: string;
  title: string;
  description: string;
  productType: string;
  formattedPrice?: string;
  priceCurrencyCode?: string;
  priceAmountMicros?: number;
  subscriptionOfferDetails?: SubscriptionOffer[];
}

export interface GetProductsResponse {
  products: Product[];
}

export interface Purchase {
  orderId?: string;
  packageName: string;
  productId: string;
  purchaseTime: number;
  purchaseToken: string;
  purchaseState: number;
  isAutoRenewing: boolean;
  isAcknowledged: boolean;
  originalJson: string;
  signature: string;
}

export interface RestorePurchasesResponse {
  purchases: Purchase[];
}

export interface PurchaseHistoryRecord {
  productId: string;
  purchaseTime: number;
  purchaseToken: string;
  quantity: number;
  originalJson: string;
  signature: string;
}

export interface GetPurchaseHistoryResponse {
  history: PurchaseHistoryRecord[];
}

export interface AcknowledgePurchaseResponse {
  success: boolean;
}

export enum PurchaseState {
  PURCHASED = 0,
  CANCELED = 1,
  PENDING = 2,
}

export interface ProductStatus {
  productId: string;
  isOwned: boolean;
  purchaseState?: PurchaseState;
  purchaseTime?: number;
  expirationTime?: number;
  isAutoRenewing?: boolean;
  isAcknowledged?: boolean;
  purchaseToken?: string;
}

export async function initialize(): Promise<InitializeResponse> {
  return await invoke<InitializeResponse>("plugin:iap|initialize");
}

export async function getProducts(
  productIds: string[],
  productType: "subs" | "inapp" = "subs",
): Promise<GetProductsResponse> {
  return await invoke<GetProductsResponse>("plugin:iap|get_products", {
    payload: {
      productIds,
      productType,
    },
  });
}

export async function purchase(
  productId: string,
  productType: "subs" | "inapp" = "subs",
  offerToken?: string,
): Promise<Purchase> {
  return await invoke<Purchase>("plugin:iap|purchase", {
    payload: {
      productId,
      productType,
      offerToken,
    },
  });
}

export async function restorePurchases(
  productType: "subs" | "inapp" = "subs",
): Promise<RestorePurchasesResponse> {
  return await invoke<RestorePurchasesResponse>(
    "plugin:iap|restore_purchases",
    {
      payload: {
        productType,
      },
    },
  );
}

export async function getPurchaseHistory(): Promise<GetPurchaseHistoryResponse> {
  return await invoke<GetPurchaseHistoryResponse>(
    "plugin:iap|get_purchase_history",
  );
}

export async function acknowledgePurchase(
  purchaseToken: string,
): Promise<AcknowledgePurchaseResponse> {
  return await invoke<AcknowledgePurchaseResponse>(
    "plugin:iap|acknowledge_purchase",
    {
      payload: {
        purchaseToken,
      },
    },
  );
}

export async function getProductStatus(
  productId: string,
  productType: "subs" | "inapp" = "subs",
): Promise<ProductStatus> {
  return await invoke<ProductStatus>("plugin:iap|get_product_status", {
    payload: {
      productId,
      productType,
    },
  });
}

// Event listener for purchase updates
export function onPurchaseUpdated(
  callback: (purchase: Purchase) => void,
): () => void {
  const unlisten = listen<Purchase>("purchaseUpdated", (event) => {
    callback(event.payload);
  });

  return () => {
    unlisten.then((fn: () => void) => fn());
  };
}
