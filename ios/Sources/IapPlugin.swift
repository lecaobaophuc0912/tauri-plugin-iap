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
class IapPlugin: Plugin {
    
    public override func load(webview: WKWebView) {
        super.load(webview: webview)
        
        // Listen for StoreKit notifications instead of Task
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreKitNotification),
            name: .storeKitTransactionUpdated,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleStoreKitNotification(_ notification: Notification) {
        // Handle transaction updates when they occur
        // This will be called when StoreKit sends notifications
        // We'll handle transactions in the individual methods instead
        print("StoreKit transaction notification received")
    }
    
    @objc public func initialize(_ invoke: Invoke) throws {
        // StoreKit 1 doesn't require explicit initialization
        invoke.resolve(["success": true])
    }
    
    @objc public func getProducts(_ invoke: Invoke) throws {
        try await self.getProducts(invoke)
    }

    public func getProducts(_ invoke: Invoke) async throws {
        let args = try invoke.parseArgs(GetProductsArgs.self)
        
        // Store the invoke for later use
        self.pendingInvoke = invoke
        self.isPurchaseRequest = false
        
        // Create products request
        let productIdentifiers = Set(args.productIds)
        self.productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        self.productsRequest?.delegate = self
        self.productsRequest?.start()
    }
    
    @objc public func purchase(_ invoke: Invoke) throws {
        try await self.purchase(invoke)
    }

    public func purchase(_ invoke: Invoke) async throws {
        let args = try invoke.parseArgs(PurchaseArgs.self)
        
        do {
            let products = try await Product.products(for: [args.productId])
            guard let product = products.first else {
                invoke.reject("Product not found")
                return
            }
            
            // Prepare purchase options
            var purchaseOptions: Set<Product.PurchaseOption> = []
            
            // Add appAccountToken if provided (must be a valid UUID)
            if let appAccountToken = args.appAccountToken {
                guard let uuid = UUID(uuidString: appAccountToken) else {
                    invoke.reject("Invalid appAccountToken: must be a valid UUID string")
                    return
                }
                purchaseOptions.insert(.appAccountToken(uuid))
            }
            
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
                    
                    // Emit purchase updated event
                    trigger("purchaseUpdated", data: purchase as! JSObject)
                    
                    invoke.resolve(purchase)
                    
                case .unverified(_, _):
                    invoke.reject("Transaction verification failed")
                }
                
            case .userCancelled:
                invoke.reject("Purchase cancelled by user")
                
            case .pending:
                invoke.reject("Purchase is pending")
                
            @unknown default:
                invoke.reject("Unknown purchase result")
            }
        } catch {
            invoke.reject("Purchase failed: \(error.localizedDescription)")
        }
    }
    
    @objc public func restorePurchases(_ invoke: Invoke) throws {
        try await self.restorePurchases(invoke)
    }

    public func restorePurchases(_ invoke: Invoke) async throws {
        let args = try? invoke.parseArgs(RestorePurchasesArgs.self)
        var purchases: [[String: Any]] = []
        
        do {
            // Get all current entitlements
            for await result in Transaction.currentEntitlements {
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
            
            invoke.resolve(["purchases": purchases])
        } catch {
            invoke.reject("Failed to restore purchases: \(error.localizedDescription)")
        }
    }

    @objc public func getPurchaseHistory(_ invoke: Invoke) throws {
        try await self.getPurchaseHistory(invoke)
    }

    public func getPurchaseHistory(_ invoke: Invoke) async throws {
        var history: [[String: Any]] = []
        
        do {
            // Get all transactions (including expired ones)
            for await result in Transaction.all {
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
            
            invoke.resolve(["history": history])
        } catch {
            invoke.reject("Failed to get purchase history: \(error.localizedDescription)")
        }
    }
    
    @objc public func acknowledgePurchase(_ invoke: Invoke) throws {
        // iOS automatically acknowledges purchases, so this is a no-op
        invoke.resolve(["success": true])
    }
    
    @objc public func getProductStatus(_ invoke: Invoke) throws {
        try await self.getProductStatus(invoke)
    }

    public func getProductStatus(_ invoke: Invoke) async throws {
        let args = try invoke.parseArgs(GetProductStatusArgs.self)
        
        var statusResult: [String: Any] = [
            "productId": args.productId,
            "isOwned": false
        ]
        
        // Check current entitlements for the specific product
        for await result in Transaction.currentEntitlements {
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
        
        invoke.resolve(statusResult)
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
    
    // MARK: - Helper Methods
    
    private func createPurchaseObject(from transaction: SKPaymentTransaction) -> [String: Any] {
        return [
            "orderId": transaction.transactionIdentifier ?? "",
            "packageName": Bundle.main.bundleIdentifier ?? "",
            "productId": transaction.payment.productIdentifier,
            "purchaseTime": Int(transaction.transactionDate?.timeIntervalSince1970 ?? 0 * 1000),
            "purchaseToken": transaction.transactionIdentifier ?? "",
            "purchaseState": transaction.transactionState == .purchased ? 0 : 1,
            "isAutoRenewing": nil, // StoreKit 1 doesn't provide this info directly
            "isAcknowledged": nil,
            "originalJson": "", // Not available in StoreKit 1
            "signature": ""      // Not available in StoreKit 1
        ]
    }
    
}

@_cdecl("init_plugin_iap")
func initPlugin() -> Plugin {
        return IapPlugin()
}