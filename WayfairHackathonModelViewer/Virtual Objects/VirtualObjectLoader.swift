/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A type which loads and tracks virtual objects.
*/

import Foundation
import ARKit
import GLTFSceneKit

typealias WayfairModelLoadSuccessHandler = (VirtualObject) -> Void
typealias WayfairModelLoadFailureHandler = (WayfairModelError) -> Void

enum WayfairModelError: Error {
    case invalidURL
    case invalidResponse
    case noModelForSKU
    case invalidModel
    
    var errorDescription: String {
        switch self {
        case .invalidURL: return "Failed to create a valid HTTPS URL"
        case .invalidResponse: return "Failed to parse returned data to JSON"
        case .noModelForSKU: return "Failed to find a GLTF model for the given SKU"
        case .invalidModel: return "Failed to parse the GLTF model for the given SKU"
        }
    }
}

struct WayfairProduct: Decodable {
    var sku: String
    var productName: String
    var productDescription: String
    var productPageURL: String
    var className: String
    var salePrice: Float
    var thumbnailImageURL: String
    
    var modelInfo: WayfairModelInfo
    
    enum CodingKeys: String, CodingKey {
        case sku
        case productName = "product_name"
        case productDescription = "product_description"
        case productPageURL = "product_page_url"
        case className = "class_name"
        case salePrice = "sale_price"
        case thumbnailImageURL = "thumbnail_image_url"
        case modelInfo = "model"
    }
}

struct WayfairModelInfo: Decodable {
    var dimensions: WayfairModelDimensions?
    var glb: String
    var obj: String
    
    enum CodingKeys: String, CodingKey {
        case dimensions = "dimensions_inches"
        case glb
        case obj
    }
}

struct WayfairModelDimensions: Decodable {
    var x: Float
    var y: Float
    var z: Float
}

struct APICredentials {
    let username: String
    let apiKey: String
    
    var authorizationHeader: [String: Any]? {
        guard let authStringData = "\(username):\(apiKey)".data(using: .utf8) else {
            return nil
        }
        
        let authHeaderValue = "Basic \(authStringData.base64EncodedString())"
        return ["Authorization" : authHeaderValue]
    }
}

/**
 Loads multiple `VirtualObject`s on a background queue to be able to display the
 objects quickly once they are needed.
*/
class VirtualObjectLoader {
    
    private enum Constants {
        static let baseURLString = "https://wayfair.com/3dapi/models"
    }
    
    private(set) var loadedObjects = [VirtualObject]()
    private(set) var isLoading = false
    
    private var urlSession: URLSession?
    
    // MARK: - Removing Objects
    
    func removeAllVirtualObjects() {
        // Reverse the indices so we don't trample over indices as objects are removed.
        for index in loadedObjects.indices.reversed() {
            removeVirtualObject(at: index)
        }
    }
    
    func removeVirtualObject(at index: Int) {
        guard loadedObjects.indices.contains(index) else { return }
        
        loadedObjects[index].removeFromParentNode()
        loadedObjects.remove(at: index)
    }
    
    // MARK: - Loading Wayfair Models
    
    func loadWayfairModel(forSKU sku: String?, credentials: APICredentials? = nil, successHandler: @escaping WayfairModelLoadSuccessHandler, failureHandler: @escaping WayfairModelLoadFailureHandler) {
        isLoading = true
        print("Loading Wayfair 3D model \(sku != nil ? "For SKU \(sku!)" : "")...")
        
        let overriddenSuccessHandler: WayfairModelLoadSuccessHandler = { [weak self] (virtualObject: VirtualObject) in
            self?.isLoading = false
            self?.loadedObjects.append(virtualObject)
            
            successHandler(virtualObject)
        }
        
        let overriddenFailureHandler: WayfairModelLoadFailureHandler = { [weak self] (error: WayfairModelError) in
            self?.isLoading = false
            failureHandler(error)
        }
    
        let urlSuccess = { [weak self] (url: URL) in
            print("Successfully fetched model URL.  Attempting to load decode GLTF model...")
            DispatchQueue.global(qos: .background).async {
                self?.loadModelForSKU(sku, fromUrl: url,
                                      successHandler: overriddenSuccessHandler,
                                      failureHandler: overriddenFailureHandler)
            }
        }
        
        let urlFailure = { (error: WayfairModelError) in
            overriddenFailureHandler(error)
        }
        
        print("Fetching model URL...")
        fetchModelURL(forSKU: sku, credentials: credentials, successHandler: urlSuccess, failureHandler: urlFailure)
    }
    
    private func fetchModelURL(forSKU sku: String?, credentials: APICredentials? = nil, successHandler: @escaping (URL) -> Void, failureHandler: @escaping (WayfairModelError) -> Void) {
        let requestURL: URL
        if let theSKU = sku {
            requestURL = URL(string: Constants.baseURLString + "?sku=\(theSKU)")!
        } else {
            requestURL = URL(string: Constants.baseURLString)!
        }

        var urlSession = URLSession.shared
        if let credentials = credentials, let authHeader = credentials.authorizationHeader {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.httpAdditionalHeaders = authHeader
            urlSession = URLSession(configuration: sessionConfig)
        }
        
        let dataTask = urlSession.dataTask(with: requestURL) { (data, response, error) in
            if let responseData = data {
                self.didLoadModelURLData(responseData, lookingForSKU: sku, successHandler: successHandler, failureHandler: failureHandler)
            } else {
                failureHandler(.invalidResponse)
            }
        }
        dataTask.resume()
    }
    
    private func didLoadModelURLData(_ data: Data, lookingForSKU sku: String?, successHandler: (URL) -> Void, failureHandler: @escaping (WayfairModelError) -> Void) {
        do {
            let products = try JSONDecoder().decode([WayfairProduct].self, from: data)
            
            var modelURL: URL?
            if let sku = sku, let resultForSKU = products.first(where: { (product) -> Bool in product.sku == sku }),
               let skuModelURL = URL(string: resultForSKU.modelInfo.glb) {
                modelURL = skuModelURL
            } else if let firstResultModelURLString = products.first?.modelInfo.glb,
                      let firstResultModelURL = URL(string: firstResultModelURLString) {
                modelURL = firstResultModelURL
            }

            guard let url = modelURL else {
                failureHandler(.noModelForSKU)
                return
            }
            
            successHandler(url)
        } catch {
            failureHandler(.invalidResponse)
        }
    }
    
    private func loadModelForSKU(_ sku: String?, fromUrl url: URL, successHandler: @escaping WayfairModelLoadSuccessHandler, failureHandler: @escaping WayfairModelLoadFailureHandler) {
        do {
            let gltfScene = try GLTFSceneSource(url: url).scene()
            guard let modelNode = gltfScene.rootNode.childNodes.first else {
                failureHandler(.invalidModel)
                return
            }
            
            // Find the shadow plane and set its SCNMaterial's lightingModel to .constant so it doesn't reflect any light
            let shadowPlaneNode = modelNode.childNodes { (node, stop) -> Bool in
                if node.name?.contains("shadow") ?? false {
                    stop.pointee = true
                    return true
                } else {
                    return false
                }
            }.first
            
            let shadowPlaneGeometry = shadowPlaneNode?.childNodes(passingTest: { (node, stop) -> Bool in
                if node.geometry != nil {
                    stop.pointee = true
                    return true
                } else {
                    return false
                }
            }).first?.geometry
            shadowPlaneGeometry?.firstMaterial?.lightingModel = .constant
            
            let modelName = sku ?? "WayfairModel"
            let virtualObject = VirtualObject(modelName: modelName, wayfairModelNode: modelNode)
            
            DispatchQueue.main.async {
                print("Successfully decoded GLTF model.  Returning to sender...")
                successHandler(virtualObject)
            }
        } catch {
            DispatchQueue.main.async {
                failureHandler(.invalidModel)
            }
        }
    }
}
