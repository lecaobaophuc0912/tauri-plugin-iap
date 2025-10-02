import Tauri
import UIKit
import WebKit
import StoreKit
import Foundation

class InitializeArgs: Decodable {}

class GetProductsArgs: Decodable {
    let productIds: [String]
    let productType: String
}

class PurchaseArgs: Decodable {
    let productId: String
    let productType: String?
    let offerToken: String?
    let appAccountToken: String?
}

class RestorePurchasesArgs: Decodable {
    let productType: String?
}

class GetPurchaseHistoryArgs: Decodable {}

class AcknowledgePurchaseArgs: Decodable {
    let purchaseToken: String
}

class GetProductStatusArgs: Decodable {
    let productId: String
    let productType: String?
}

enum PurchaseStateValue: Int {
    case purchased = 0
    case canceled = 1
    case pending = 2
}

@available(iOS 15.0, *)
@MainActor
class IapPlugin: Plugin {
    private var updateListenerTask: Task<Void, Never>?
    private var activeTasks: Set<Task<Void, Never>> = []
        
    public override func load(webview: WKWebView) {
        super.load(webview: webview)

        // Start listening for transaction updates
        updateListenerTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                for await update in Transaction.updates {
                    // Check if task is cancelled
                    try Task.checkCancellation()
                    
                    await self.handleTransactionUpdate(update)
                }
            } catch is CancellationError {
                // Task was cancelled - this is expected
                print("Transaction listener task cancelled")
            } catch {
                // Other error occurred
                print("Transaction listener task ended with error: \(error)")
            }
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
        updateListenerTask = nil
        
        // Cancel all active tasks
        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }
    
    @objc public func initialize(_ invoke: Invoke) throws {
        // StoreKit 2 doesn't require explicit initialization
        invoke.resolve(["success": true])
    }
    
    @objc public func getProducts(_ invoke: Invoke) throws {
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try Task.checkCancellation()
                try await self.getProducts(invoke)
            } catch is CancellationError {
                // Task was cancelled - don't call invoke methods
                print("GetProducts task cancelled")
            } catch {
                await MainActor.run {
                    invoke.reject("Failed to get products: \(error.localizedDescription)")
                }
            }
        }
        
        // Track the task for cleanup
        activeTasks.insert(task)
        
        // Remove task when completed
        Task {
            await task.value
            await MainActor.run {
                self.activeTasks.remove(task)
            }
        }
    }

    public func getProducts(_ invoke: Invoke) async throws {
        let args = try invoke.parseArgs(GetProductsArgs.self)
        
        do {
            try Task.checkCancellation()
            let products = try await Product.products(for: args.productIds)
            var productsArray: [[String: Any]] = []
            
            for product in products {
                try Task.checkCancellation()
                
                var productDict: [String: Any] = [
                    "productId": product.id,
                    "title": product.displayName,
                    "description": product.description,
                    "productType": product.type.rawValue
                ]
                
                // Add pricing information
                productDict["formattedPrice"] = product.displayPrice
                productDict["priceCurrencyCode"] = getCurrencyCode(for: product)
                
                // Handle subscription-specific information
                if product.type == .autoRenewable || product.type == .nonRenewable {
                    if let subscription = product.subscription {
                        var subscriptionOffers: [[String: Any]] = []
                        
                        // Add introductory offer if available
                        if let introOffer = subscription.introductoryOffer {
                            let offer: [String: Any] = [
                                "offerToken": "",  // iOS doesn't use offer tokens
                                "basePlanId": "",
                                "offerId": introOffer.id ?? "",
                                "pricingPhases": [[
                                    "formattedPrice": introOffer.displayPrice,
                                    "priceCurrencyCode": getCurrencyCode(for: product),
                                    "priceAmountMicros": 0,  // Not available in StoreKit 2
                                    "billingPeriod": formatSubscriptionPeriod(introOffer.period),
                                    "billingCycleCount": introOffer.periodCount,
                                    "recurrenceMode": 0
                                ]]
                            ]
                            subscriptionOffers.append(offer)
                        }
                        
                        // Add regular subscription info
                        let regularOffer: [String: Any] = [
                            "offerToken": "",
                            "basePlanId": "",
                            "offerId": "",
                            "pricingPhases": [[
                                "formattedPrice": product.displayPrice,
                                "priceCurrencyCode": getCurrencyCode(for: product),
                                "priceAmountMicros": 0,
                                "billingPeriod": formatSubscriptionPeriod(subscription.subscriptionPeriod),
                                "billingCycleCount": 0,
                                "recurrenceMode": 1
                            ]]
                        ]
                        subscriptionOffers.append(regularOffer)
                        
                        productDict["subscriptionOfferDetails"] = subscriptionOffers
                    }
                } else {
                    // One-time purchase
                    productDict["priceAmountMicros"] = 0  // Not available in StoreKit 2
                }
                
                productsArray.append(productDict)
            }
            
            await MainActor.run {
                invoke.resolve(["products": productsArray])
            }
        } catch is CancellationError {
            throw error
        } catch {
            await MainActor.run {
                invoke.reject("Failed to fetch products: \(error.localizedDescription)")
            }
        }
    }
    
    @objc public func purchase(_ invoke: Invoke) throws {
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try Task.checkCancellation()
                try await self.purchase(invoke)
            } catch is CancellationError {
                // Task was cancelled - don't call invoke methods
                print("Purchase task cancelled")
            } catch {
                await MainActor.run {
                    invoke.reject("Purchase failed: \(error.localizedDescription)")
                }
            }
        }
        
        // Track the task for cleanup
        activeTasks.insert(task)
        
        // Remove task when completed
        Task {
            await task.value
            await MainActor.run {
                self.activeTasks.remove(task)
            }
        }
    }

    public func purchase(_ invoke: Invoke) async throws {
        let args = try invoke.parseArgs(PurchaseArgs.self)
        
        do {
            try Task.checkCancellation()
            let products = try await Product.products(for: [args.productId])
            guard let product = products.first else {
                await MainActor.run {
                    invoke.reject("Product not found")
                }
                return
            }
            
            // Prepare purchase options
            var purchaseOptions: Set<Product.PurchaseOption> = []
            
            // Add appAccountToken if provided (must be a valid UUID)
            if let appAccountToken = args.appAccountToken {
                guard let uuid = UUID(uuidString: appAccountToken) else {
                    await MainActor.run {
                        invoke.reject("Invalid appAccountToken: must be a valid UUID string")
                    }
                    return
                }
                purchaseOptions.insert(.appAccountToken(uuid))
            }
            
            try Task.checkCancellation()
            
            // Initiate purchase with options
            let result = purchaseOptions.isEmpty 
                ? try await product.purchase()
                : try await product.purchase(options: purchaseOptions)
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Finish the transaction
                    await transaction.finish()
                    
                    let purchase = await createPurchaseObject(from: transaction, product: product)
                    await MainActor.run {
                        invoke.resolve(purchase)
                    }
                    
                case .unverified(_, _):
                    await MainActor.run {
                        invoke.reject("Transaction verification failed")
                    }
                }
                
            case .userCancelled:
                await MainActor.run {
                    invoke.reject("Purchase cancelled by user")
                }
                
            case .pending:
                await MainActor.run {
                    invoke.reject("Purchase is pending")
                }
                
            @unknown default:
                await MainActor.run {
                    invoke.reject("Unknown purchase result")
                }
            }
        } catch is CancellationError {
            throw error
        } catch {
            await MainActor.run {
                invoke.reject("Purchase failed: \(error.localizedDescription)")
            }
        }
    }
    
    @objc public func restorePurchases(_ invoke: Invoke) throws {
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try Task.checkCancellation()
                try await self.restorePurchases(invoke)
            } catch is CancellationError {
                // Task was cancelled - don't call invoke methods
                print("RestorePurchases task cancelled")
            } catch {
                await MainActor.run {
                    invoke.reject("Failed to restore purchases: \(error.localizedDescription)")
                }
            }
        }
        
        // Track the task for cleanup
        activeTasks.insert(task)
        
        // Remove task when completed
        Task {
            await task.value
            await MainActor.run {
                self.activeTasks.remove(task)
            }
        }
    }

    public func restorePurchases(_ invoke: Invoke) async throws {
        let args = try? invoke.parseArgs(RestorePurchasesArgs.self)
        var purchases: [[String: Any]] = []
        
        do {
            // Get all current entitlements
            for await result in Transaction.currentEntitlements {
                try Task.checkCancellation()
                
                switch result {
                case .verified(let transaction):
                    if let product = try? await Product.products(for: [transaction.productID]).first {
                        // Filter by product type if specified
                        if let requestedType = args?.productType {
                            let productTypeMatches: Bool
                            switch requestedType {
                            case "subs":
                                productTypeMatches = (product.type == .autoRenewable || product.type == .nonRenewable)
                            case "inapp":
                                productTypeMatches = (product.type == .consumable || product.type == .nonConsumable)
                            default:
                                productTypeMatches = true
                            }
                            
                            if productTypeMatches {
                                let purchase = await createPurchaseObject(from: transaction, product: product)
                                purchases.append(purchase)
                            }
                        } else {
                            // No filter, include all
                            let purchase = await createPurchaseObject(from: transaction, product: product)
                            purchases.append(purchase)
                        }
                    }
                case .unverified(_, _):
                    // Skip unverified transactions
                    continue
                }
            }
            
            await MainActor.run {
                invoke.resolve(["purchases": purchases])
            }
        } catch is CancellationError {
            throw error
        } catch {
            await MainActor.run {
                invoke.reject("Failed to restore purchases: \(error.localizedDescription)")
            }
        }
    }

    @objc public func getPurchaseHistory(_ invoke: Invoke) throws {
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try Task.checkCancellation()
                try await self.getPurchaseHistory(invoke)
            } catch is CancellationError {
                // Task was cancelled - don't call invoke methods
                print("GetPurchaseHistory task cancelled")
            } catch {
                await MainActor.run {
                    invoke.reject("Failed to get purchase history: \(error.localizedDescription)")
                }
            }
        }
        
        // Track the task for cleanup
        activeTasks.insert(task)
        
        // Remove task when completed
        Task {
            await task.value
            await MainActor.run {
                self.activeTasks.remove(task)
            }
        }
    }

    public func getPurchaseHistory(_ invoke: Invoke) async throws {
        var history: [[String: Any]] = []
        
        do {
            // Get all transactions (including expired ones)
            for await result in Transaction.all {
                try Task.checkCancellation()
                
                switch result {
                case .verified(let transaction):
                    let record: [String: Any] = [
                        "productId": transaction.productID,
                        "purchaseTime": Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
                        "purchaseToken": String(transaction.id),
                        "quantity": transaction.purchasedQuantity,
                        "originalJson": "",  // Not available in StoreKit 2
                        "signature": ""      // Not available in StoreKit 2
                    ]
                    history.append(record)
                case .unverified(_, _):
                    continue
                }
            }
            
            await MainActor.run {
                invoke.resolve(["history": history])
            }
        } catch is CancellationError {
            throw error
        } catch {
            await MainActor.run {
                invoke.reject("Failed to get purchase history: \(error.localizedDescription)")
            }
        }
    }
    
    @objc public func acknowledgePurchase(_ invoke: Invoke) throws {
        // iOS automatically acknowledges purchases, so this is a no-op
        invoke.resolve(["success": true])
    }
    
    @objc public func getProductStatus(_ invoke: Invoke) throws {
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try Task.checkCancellation()
                try await self.getProductStatus(invoke)
            } catch is CancellationError {
                // Task was cancelled - don't call invoke methods
                print("GetProductStatus task cancelled")
            } catch {
                await MainActor.run {
                    invoke.reject("Failed to get product status: \(error.localizedDescription)")
                }
            }
        }
        
        // Track the task for cleanup
        activeTasks.insert(task)
        
        // Remove task when completed
        Task {
            await task.value
            await MainActor.run {
                self.activeTasks.remove(task)
            }
        }
    }

    public func getProductStatus(_ invoke: Invoke) async throws {
        let args = try invoke.parseArgs(GetProductStatusArgs.self)
        
        var statusResult: [String: Any] = [
            "productId": args.productId,
            "isOwned": false
        ]
        
        do {
            // Check current entitlements for the specific product
            for await result in Transaction.currentEntitlements {
                try Task.checkCancellation()
                
                switch result {
                case .verified(let transaction):
                    if transaction.productID == args.productId {
                        statusResult["isOwned"] = true
                        statusResult["purchaseTime"] = Int(transaction.purchaseDate.timeIntervalSince1970 * 1000)
                        statusResult["purchaseToken"] = String(transaction.id)
                        statusResult["isAcknowledged"] = true  // Always true on iOS
                        
                        // Check if expired/revoked
                        if let revocationDate = transaction.revocationDate {
                            statusResult["purchaseState"] = PurchaseStateValue.canceled.rawValue
                            statusResult["isOwned"] = false
                            statusResult["expirationTime"] = Int(revocationDate.timeIntervalSince1970 * 1000)
                        } else if let expirationDate = transaction.expirationDate {
                            if expirationDate < Date() {
                                statusResult["purchaseState"] = PurchaseStateValue.canceled.rawValue
                                statusResult["isOwned"] = false
                            } else {
                                statusResult["purchaseState"] = PurchaseStateValue.purchased.rawValue
                            }
                            statusResult["expirationTime"] = Int(expirationDate.timeIntervalSince1970 * 1000)
                        } else {
                            statusResult["purchaseState"] = PurchaseStateValue.purchased.rawValue
                        }
                        
                        // Check subscription renewal status if it's a subscription
                        if let product = try? await Product.products(for: [args.productId]).first {
                            if product.type == .autoRenewable {
                                // Check subscription status
                                if let statuses = try? await product.subscription?.status {
                                    for status in statuses {
                                        if status.state == .subscribed {
                                            statusResult["isAutoRenewing"] = true
                                        } else if status.state == .expired {
                                            statusResult["isAutoRenewing"] = false
                                            statusResult["purchaseState"] = PurchaseStateValue.canceled.rawValue
                                            statusResult["isOwned"] = false
                                        } else if status.state == .inGracePeriod {
                                            statusResult["isAutoRenewing"] = true
                                            statusResult["purchaseState"] = PurchaseStateValue.purchased.rawValue
                                        } else {
                                            statusResult["isAutoRenewing"] = false
                                        }
                                        break
                                    }
                                }
                            }
                        }
                        
                        break
                    }
                case .unverified(_, _):
                    // Skip unverified transactions
                    continue
                }
            }
            
            await MainActor.run {
                invoke.resolve(statusResult)
            }
        } catch is CancellationError {
            throw error
        } catch {
            await MainActor.run {
                invoke.reject("Failed to get product status: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            try Task.checkCancellation()
            
            switch result {
            case .verified(let transaction):
                do {
                    // Get product details
                    let products = try await Product.products(for: [transaction.productID])
                    if let product = products.first {
                        let purchase = await createPurchaseObject(from: transaction, product: product)
                        
                        // Safely convert to JSObject-compatible format
                        if let jsObject = purchase as? JSObject {
                            await MainActor.run {
                                self.trigger("purchaseUpdated", data: jsObject)
                            }
                        }
                    }
                    
                    // Always finish transactions
                    await transaction.finish()
                } catch {
                    print("Error handling transaction update: \(error)")
                    // Still finish the transaction even if there's an error
                    await transaction.finish()
                }
                
            case .unverified(_, _):
                // Handle unverified transaction
                print("Received unverified transaction")
                break
            }
        } catch is CancellationError {
            // Task was cancelled - this is expected
            print("Transaction update handler cancelled")
        } catch {
            print("Error in transaction update handler: \(error)")
        }
    }
    
    private func createPurchaseObject(from transaction: Transaction, product: Product) async -> [String: Any] {
        var isAutoRenewing = false
        
        // Check if it's an auto-renewable subscription
        if product.type == .autoRenewable {
            // Check subscription status
            if let statuses = try? await product.subscription?.status {
                for status in statuses {
                    if status.state == .subscribed {
                        isAutoRenewing = true
                        break
                    }
                }
            }
        }
        
        return [
            "orderId": String(transaction.id),
            "packageName": Bundle.main.bundleIdentifier ?? "",
            "productId": transaction.productID,
            "purchaseTime": Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
            "purchaseToken": String(transaction.id),
            "purchaseState": transaction.revocationDate == nil ? 0 : 1,  // 0 = purchased, 1 = canceled
            "isAutoRenewing": isAutoRenewing,
            "isAcknowledged": true,  // Always true on iOS
            "originalJson": "",      // Not available in StoreKit 2
            "signature": ""          // Not available in StoreKit 2
        ]
    }
    
    private func formatSubscriptionPeriod(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return "P\(period.value)D"
        case .week:
            return "P\(period.value)W"
        case .month:
            return "P\(period.value)M"
        case .year:
            return "P\(period.value)Y"
        @unknown default:
            return "P1M"
        }
    }
    
    private func getCurrencyCode(for product: Product) -> String {
        if #available(iOS 16.0, *) {
            return product.priceFormatStyle.locale.currency?.identifier ?? ""
        } else {
            // Fallback for iOS 15: currency code not directly available
            return ""
        }
    }
}

@_cdecl("init_plugin_iap")
func initPlugin() -> Plugin {
    if #available(iOS 15.0, *) {
        return IapPlugin()
    } else {
        // Return a dummy plugin for older iOS versions
        class DummyPlugin: Plugin {
            @objc func initialize(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
            @objc func getProducts(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
            @objc func purchase(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
            @objc func restorePurchases(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
            @objc func getPurchaseHistory(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
            @objc func acknowledgePurchase(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
            @objc func getProductStatus(_ invoke: Invoke) {
                invoke.reject("IAP requires iOS 15.0 or later")
            }
        }
        return DummyPlugin()
    }
}