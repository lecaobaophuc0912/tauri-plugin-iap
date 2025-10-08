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

class IapPlugin: Plugin, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private var productsRequest: SKProductsRequest?
    private var pendingInvoke: Invoke?
    private var isPurchaseRequest: Bool = false
    private var currentAppAccountToken: String?
    
    public override init() {
        super.init()
        
        // Add as transaction observer
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    @objc public func initialize(_ invoke: Invoke) throws {
        // StoreKit 1 doesn't require explicit initialization
        invoke.resolve(["success": true])
    }
    
    @objc public func getProducts(_ invoke: Invoke) throws {
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
        let args = try invoke.parseArgs(PurchaseArgs.self)
        
        // Store the invoke for later use
        self.pendingInvoke = invoke
        self.isPurchaseRequest = true
        
        // Store appAccountToken for later use
        self.currentAppAccountToken = args.appAccountToken
        
        // First, we need to get the product to create a proper payment
        let productIdentifiers = Set([args.productId])
        self.productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        self.productsRequest?.delegate = self
        self.productsRequest?.start()
    }
    
    @objc public func restorePurchases(_ invoke: Invoke) throws {
        // Store the invoke for later use
        self.pendingInvoke = invoke
        
        // Restore completed transactions
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    @objc public func getPurchaseHistory(_ invoke: Invoke) throws {
        // StoreKit 1 doesn't provide direct access to purchase history
        // This would typically be handled server-side
        invoke.resolve(["history": []])
    }
    
    @objc public func acknowledgePurchase(_ invoke: Invoke) throws {
        // iOS automatically acknowledges purchases, so this is a no-op
        invoke.resolve(["success": true])
    }
    
    @objc public func getProductStatus(_ invoke: Invoke) throws {
        let args = try invoke.parseArgs(GetProductStatusArgs.self)
        
        // Check if product is owned by checking receipt
        let receiptURL = Bundle.main.appStoreReceiptURL
        if let receiptData = try? Data(contentsOf: receiptURL!) {
            // Parse receipt to check product ownership
            // This is a simplified version - in practice you'd parse the receipt properly
            let statusResult: [String: Any] = [
                "productId": args.productId,
                "isOwned": false, // Would be determined by receipt parsing
                "isAcknowledged": true,
                "purchaseState": PurchaseStateValue.purchased.rawValue
            ]
            invoke.resolve(statusResult)
        } else {
            let statusResult: [String: Any] = [
                "productId": args.productId,
                "isOwned": false,
                "isAcknowledged": true,
                "purchaseState": PurchaseStateValue.canceled.rawValue
            ]
            invoke.resolve(statusResult)
        }
    }
    
    // MARK: - SKProductsRequestDelegate
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        var productsArray: [[String: Any]] = []
        
        for product in response.products {
            var productDict: [String: Any] = [
                "productId": product.productIdentifier,
                "title": product.localizedTitle,
                "description": product.localizedDescription,
                "productType": "inapp" // StoreKit 1 doesn't distinguish between types
            ]
            
            // Add pricing information
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product.priceLocale
            productDict["formattedPrice"] = formatter.string(from: product.price)
            productDict["priceCurrencyCode"] = product.priceLocale.currencyCode ?? ""
            
            productsArray.append(productDict)
        }
        
        if let invoke = self.pendingInvoke {
            // Check if this is a purchase request or getProducts request
            if self.isPurchaseRequest && productsArray.count == 1 {
                // This is a purchase request, initiate the payment
                let product = response.products.first!
                let payment = SKMutablePayment(product: product)
                
                // Add appAccountToken if provided
                if let appAccountToken = self.currentAppAccountToken {
                    payment.applicationUsername = appAccountToken
                }
                
                SKPaymentQueue.default().add(payment)
            } else {
                // This is a getProducts request
                invoke.resolve(["products": productsArray])
                self.pendingInvoke = nil
                self.isPurchaseRequest = false
                self.currentAppAccountToken = nil
            }
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        if let invoke = self.pendingInvoke {
            invoke.reject("Request failed: \(error.localizedDescription)")
            self.pendingInvoke = nil
            self.isPurchaseRequest = false
            self.currentAppAccountToken = nil
        }
    }
    
    // MARK: - SKPaymentTransactionObserver
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                // Handle successful purchase
                let purchase = self.createPurchaseObject(from: transaction)
                if let invoke = self.pendingInvoke {
                    invoke.resolve(purchase)
                    self.pendingInvoke = nil
                    self.isPurchaseRequest = false
                    self.currentAppAccountToken = nil
                }
                
                // Emit event
                self.trigger("purchaseUpdated", data: purchase as! JSObject)
                
                // Finish the transaction
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .failed:
                // Handle failed purchase
                if let invoke = self.pendingInvoke {
                    if let error = transaction.error as? SKError {
                        switch error.code {
                        case .paymentCancelled:
                            invoke.reject("Purchase cancelled by user")
                        default:
                            invoke.reject("Purchase failed: \(error.localizedDescription)")
                        }
                    } else {
                        invoke.reject("Purchase failed")
                    }
                    self.pendingInvoke = nil
                    self.isPurchaseRequest = false
                    self.currentAppAccountToken = nil
                }
                
                // Finish the transaction
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .restored:
                // Handle restored purchase
                let purchase = self.createPurchaseObject(from: transaction)
                if let invoke = self.pendingInvoke {
                    invoke.resolve(["purchases": [purchase]])
                    self.pendingInvoke = nil
                    self.isPurchaseRequest = false
                    self.currentAppAccountToken = nil
                }
                
                // Finish the transaction
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .deferred:
                // Handle deferred purchase (e.g., Ask to Buy)
                if let invoke = self.pendingInvoke {
                    invoke.reject("Purchase is pending")
                    self.pendingInvoke = nil
                    self.isPurchaseRequest = false
                    self.currentAppAccountToken = nil
                }
                
            case .purchasing:
                // Transaction is being processed
                break
                
            @unknown default:
                break
            }
        }
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        // All restore transactions completed
        if let invoke = self.pendingInvoke {
            invoke.resolve(["purchases": []])
            self.pendingInvoke = nil
            self.isPurchaseRequest = false
            self.currentAppAccountToken = nil
        }
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        // Restore failed
        if let invoke = self.pendingInvoke {
            invoke.reject("Restore failed: \(error.localizedDescription)")
            self.pendingInvoke = nil
            self.isPurchaseRequest = false
            self.currentAppAccountToken = nil
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