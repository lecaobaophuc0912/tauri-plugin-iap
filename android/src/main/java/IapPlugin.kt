package app.tauri.iap

import android.app.Activity
import android.util.Log
import android.webkit.WebView
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import app.tauri.plugin.Invoke
import com.android.billingclient.api.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray

@InvokeArg
class InitializeArgs

@InvokeArg
class GetProductsArgs {
    var productIds: List<String> = emptyList()
    var productType: String = "subs" // "subs" or "inapp"
}

@InvokeArg
class PurchaseArgs {
    var productId: String = ""
    var offerToken: String? = null
}

@InvokeArg
class RestorePurchasesArgs

@InvokeArg
class GetPurchaseHistoryArgs

@InvokeArg
class AcknowledgePurchaseArgs {
    var purchaseToken: String? = null
}

@TauriPlugin
class IapPlugin(private val activity: Activity): Plugin(activity), PurchasesUpdatedListener, BillingClientStateListener {
    private lateinit var billingClient: BillingClient
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var pendingPurchaseInvoke: Invoke? = null
    private val TAG = "IapPlugin"
    
    override fun load(webView: WebView) {
        super.load(webView)
        initializeBillingClient()
    }
    
    private fun initializeBillingClient() {
        var params = PendingPurchasesParams.newBuilder()
            .enableOneTimeProducts()
            .build();

        billingClient = BillingClient.newBuilder(activity)
            .setListener(this)
            .enablePendingPurchases(params)
            .enableAutoServiceReconnection()
            .build()
    }
    
    @Command
    fun initialize(invoke: Invoke) {
        if (billingClient.isReady) {
            invoke.resolve(JSObject().put("success", true))
            return
        }
        
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    invoke.resolve(JSObject().put("success", true))
                } else {
                    invoke.reject("Billing setup failed: ${billingResult.debugMessage}")
                }
            }

            override fun onBillingServiceDisconnected() {
                Log.d(TAG, "Billing service disconnected")
            }
        })
    }
    
    @Command
    fun getProducts(invoke: Invoke) {
        val args = invoke.parseArgs(GetProductsArgs::class.java)
        
        if (!billingClient.isReady) {
            invoke.reject("Billing client not ready")
            return
        }
        
        val productType = when (args.productType) {
            "inapp" -> BillingClient.ProductType.INAPP
            "subs" -> BillingClient.ProductType.SUBS
            else -> BillingClient.ProductType.SUBS
        }
        
        val productList = args.productIds.map { productId ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(productId)
                .setProductType(productType)
                .build()
        }
        
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()
        
        billingClient.queryProductDetailsAsync(params) { billingResult: BillingResult, productDetailsResult: QueryProductDetailsResult ->
            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                val products = JSObject()
                val productsArray = productDetailsResult.productDetailsList?.map { productDetails ->
                    JSObject().apply {
                        put("productId", productDetails.productId)
                        put("title", productDetails.title)
                        put("description", productDetails.description)
                        put("productType", productDetails.productType)
                        
                        // For subscriptions, include offer details
                        if (productDetails.productType == BillingClient.ProductType.SUBS) {
                            val subscriptionOfferDetails = productDetails.subscriptionOfferDetails
                            if (!subscriptionOfferDetails.isNullOrEmpty()) {
                                val offers = subscriptionOfferDetails.map { offer ->
                                    JSObject().apply {
                                        put("offerToken", offer.offerToken)
                                        put("basePlanId", offer.basePlanId)
                                        put("offerId", offer.offerId)
                                        
                                        // Pricing phases
                                        val pricingPhases = offer.pricingPhases.pricingPhaseList.map { phase ->
                                            JSObject().apply {
                                                put("formattedPrice", phase.formattedPrice)
                                                put("priceCurrencyCode", phase.priceCurrencyCode)
                                                put("priceAmountMicros", phase.priceAmountMicros)
                                                put("billingPeriod", phase.billingPeriod)
                                                put("billingCycleCount", phase.billingCycleCount)
                                                put("recurrenceMode", phase.recurrenceMode)
                                            }
                                        }
                                        put("pricingPhases", JSONArray(pricingPhases))
                                    }
                                }
                                put("subscriptionOfferDetails", JSONArray(offers))
                            }
                        } else {
                            // For one-time products
                            val oneTimePurchaseOfferDetails = productDetails.oneTimePurchaseOfferDetails
                            if (oneTimePurchaseOfferDetails != null) {
                                put("formattedPrice", oneTimePurchaseOfferDetails.formattedPrice)
                                put("priceCurrencyCode", oneTimePurchaseOfferDetails.priceCurrencyCode)
                                put("priceAmountMicros", oneTimePurchaseOfferDetails.priceAmountMicros)
                            }
                        }
                    }
                }
                products.put("products", JSONArray(productsArray))
                invoke.resolve(products)
            } else {
                invoke.reject("Failed to fetch products: ${billingResult.debugMessage}")
            }
        }
    }
    
    @Command
    fun purchase(invoke: Invoke) {
        val args = invoke.parseArgs(PurchaseArgs::class.java)
        
        if (!billingClient.isReady) {
            invoke.reject("Billing client not ready")
            return
        }
        
        pendingPurchaseInvoke = invoke
        
        // First, get the product details
        val productList = listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(args.productId)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        )
        
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()
        
        billingClient.queryProductDetailsAsync(params) { billingResult: BillingResult, productDetailsResult: QueryProductDetailsResult ->
            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK && productDetailsResult.productDetailsList.isNotEmpty()) {
                val productDetails = productDetailsResult.productDetailsList[0]

                val productDetailsParamsList = if (args.offerToken != null) {
                    listOf(
                        BillingFlowParams.ProductDetailsParams.newBuilder()
                            .setProductDetails(productDetails)
                            .setOfferToken(args.offerToken!!)
                            .build()
                    )
                } else {
                    listOf(
                        BillingFlowParams.ProductDetailsParams.newBuilder()
                            .setProductDetails(productDetails)
                            .build()
                    )
                }
                
                val billingFlowParams = BillingFlowParams.newBuilder()
                    .setProductDetailsParamsList(productDetailsParamsList)
                    .build()
                
                val billingResult = billingClient.launchBillingFlow(activity, billingFlowParams)
                
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    pendingPurchaseInvoke = null
                    invoke.reject("Failed to launch billing flow: ${billingResult.debugMessage}")
                }
            } else {
                pendingPurchaseInvoke = null
                invoke.reject("Product not found")
            }
        }
    }
    
    @Command
    fun restorePurchases(invoke: Invoke) {
        if (!billingClient.isReady) {
            invoke.reject("Billing client not ready")
            return
        }
        
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        
        billingClient.queryPurchasesAsync(params) { billingResult, purchases ->
            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                val purchasesArray = purchases.map { purchase ->
                    JSObject().apply {
                        put("orderId", purchase.orderId)
                        put("packageName", purchase.packageName)
                        put("productId", purchase.products.firstOrNull() ?: "")
                        put("purchaseTime", purchase.purchaseTime)
                        put("purchaseToken", purchase.purchaseToken)
                        put("purchaseState", purchase.purchaseState)
                        put("isAutoRenewing", purchase.isAutoRenewing)
                        put("isAcknowledged", purchase.isAcknowledged)
                        put("originalJson", purchase.originalJson)
                        put("signature", purchase.signature)
                    }
                }
                
                val result = JSObject()
                result.put("purchases", purchasesArray)
                invoke.resolve(result)
            } else {
                invoke.reject("Failed to restore purchases: ${billingResult.debugMessage}")
            }
        }
    }
    
    @Command
    fun getPurchaseHistory(invoke: Invoke) {
        invoke.reject("Purchase history is not supported")
    }
    
    @Command
    fun acknowledgePurchase(invoke: Invoke) {
        val purchaseToken = invoke.parseArgs(AcknowledgePurchaseArgs::class.java).purchaseToken
        
        if (purchaseToken == null) {
            invoke.reject("Purchase token is required")
            return
        }
        
        if (!billingClient.isReady) {
            invoke.reject("Billing client not ready")
            return
        }
        
        val acknowledgePurchaseParams = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchaseToken)
            .build()
        
        billingClient.acknowledgePurchase(acknowledgePurchaseParams) { billingResult ->
            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                invoke.resolve(JSObject().put("success", true))
            } else {
                invoke.reject("Failed to acknowledge purchase: ${billingResult.debugMessage}")
            }
        }
    }
    
    override fun onPurchasesUpdated(billingResult: BillingResult, purchases: List<Purchase>?) {
        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                purchases?.let { purchaseList ->
                    for (purchase in purchaseList) {
                        handlePurchase(purchase)
                    }
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                pendingPurchaseInvoke?.reject("Purchase cancelled by user")
                pendingPurchaseInvoke = null
            }
            else -> {
                pendingPurchaseInvoke?.reject("Purchase failed: ${billingResult.debugMessage}")
                pendingPurchaseInvoke = null
            }
        }
    }
    
    private fun handlePurchase(purchase: Purchase) {
        if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
            val purchaseData = JSObject().apply {
                put("orderId", purchase.orderId)
                put("packageName", purchase.packageName)
                put("productId", purchase.products.firstOrNull() ?: "")
                put("purchaseTime", purchase.purchaseTime)
                put("purchaseToken", purchase.purchaseToken)
                put("purchaseState", purchase.purchaseState)
                put("isAutoRenewing", purchase.isAutoRenewing)
                put("isAcknowledged", purchase.isAcknowledged)
                put("originalJson", purchase.originalJson)
                put("signature", purchase.signature)
            }
            
            pendingPurchaseInvoke?.resolve(purchaseData)
            pendingPurchaseInvoke = null
            
            // Emit event for purchase state change
            trigger("purchaseUpdated", purchaseData)
        }
    }
    
    override fun onBillingSetupFinished(billingResult: BillingResult) {
        if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            Log.d(TAG, "Billing setup finished successfully")
        }
    }
    
    override fun onBillingServiceDisconnected() {
        Log.d(TAG, "Billing service disconnected")
    }
}