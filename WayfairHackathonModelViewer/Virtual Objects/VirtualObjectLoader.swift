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

struct APIResponse: Decodable {
    var modelInfo: GLTFModelInfo?
    
    enum CodingKeys: String, CodingKey {
        case modelInfo = "product_3d_info"
    }
}

struct GLTFModelInfo: Decodable {
    var modelURLString: String?
    
    enum CodingKeys: String, CodingKey {
        case modelURLString = "preferred_gltf_url"
    }
}

/**
 Loads multiple `VirtualObject`s on a background queue to be able to display the
 objects quickly once they are needed.
*/
class VirtualObjectLoader {
    
    private enum Constants {
        static let baseURLString = "https://www.wayfair.com/v/product/get_model_info?_format=json&clearcache=true&sku="
    }
    
    private(set) var loadedObjects = [VirtualObject]()
    private(set) var isLoading = false
    
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
    
    func loadWayfairModel(forSKU sku: String, successHandler: @escaping WayfairModelLoadSuccessHandler, failureHandler: @escaping WayfairModelLoadFailureHandler) {
        isLoading = true
        print("Loading Wayfair 3D model for SKU \(sku)...")
        
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
            failureHandler(error)
        }
        
        print("Fetching model URL...")
        fetchModelURL(forSKU: sku, successHandler: urlSuccess, failureHandler: urlFailure)
    }
    
    private func fetchModelURL(forSKU sku: String, successHandler: @escaping (URL) -> Void, failureHandler: @escaping (WayfairModelError) -> Void) {
        guard let urlForSKU = URL(string: Constants.baseURLString + sku) else {
            failureHandler(.invalidURL)
            return
        }
        
        let dataTask = URLSession.shared.dataTask(with: urlForSKU) { (data, response, error) in
            if let responseData = data {
                self.didLoadModelURLData(responseData, successHandler: successHandler, failureHandler: failureHandler)
            } else {
                failureHandler(.invalidResponse)
            }
        }
        dataTask.resume()
    }
    
    private func didLoadModelURLData(_ data: Data, successHandler: (URL) -> Void, failureHandler: @escaping (WayfairModelError) -> Void) {
        do {
            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            if let modelURLString = apiResponse.modelInfo?.modelURLString, let modelURL = URL(string: modelURLString) {
                successHandler(modelURL)
            } else {
                failureHandler(.noModelForSKU)
            }
        } catch {
            failureHandler(.noModelForSKU)
        }
    }
    
    private func loadModelForSKU(_ sku: String, fromUrl url: URL, successHandler: @escaping WayfairModelLoadSuccessHandler, failureHandler: @escaping WayfairModelLoadFailureHandler) {
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
            
            let virtualObject = VirtualObject(sku: sku, wayfairModelNode: modelNode)
            
            DispatchQueue.main.async {
                print("Successfully decoded GLTF model for \(sku).  Returning to sender...")
                successHandler(virtualObject)
            }
        } catch {
            DispatchQueue.main.async {
                failureHandler(.invalidModel)
            }
        }
    }
}
