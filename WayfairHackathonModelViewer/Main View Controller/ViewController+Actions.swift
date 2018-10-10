/*
See LICENSE folder for this sample’s licensing information.

Abstract:
UI Actions for the main view controller.
*/

import UIKit
import SceneKit

extension ViewController: UIGestureRecognizerDelegate {
    
    enum SegueIdentifier: String {
        case showObjects
    }
    
    // MARK: - Interface Actions
    
    /// Displays the SKU entry view from the `addObjectButton` or in response to a tap gesture in the `sceneView`.
    @IBAction func showSKUEntryView() {
        // Ensure adding objects is an available action and we are not loading another object (to avoid concurrent modifications of the scene).
        guard !addObjectButton.isHidden && !virtualObjectLoader.isLoading else { return }
        
        statusViewController.cancelScheduledMessage(for: .contentPlacement)
        
        let controller = UIAlertController(title: "Enter a SKU", message: nil, preferredStyle: .alert)
        let loadModelAction = UIAlertAction(title: "Load", style: .default) { [weak self] (_) in
            guard let sku = controller.textFields?.first?.text?.uppercased() else {
                return
            }
            
            self?.loadModelForSKU(sku)
        }
        let loadReclinerModelAction = UIAlertAction(title: "Load Recliner (VVRE3131)", style: .default) { [weak self] (_) in
            self?.loadModelForSKU("VVRE3131")
        }
        controller.addAction(loadModelAction)
        controller.addAction(loadReclinerModelAction)
        controller.addTextField { (textField) in
            textField.placeholder = "SKU"
        }
        present(controller, animated: true, completion: nil)
    }
    
    private func loadModelForSKU(_ sku: String) {
        let success = { [weak self] (model: VirtualObject) -> Void in
            self?.addWayfairVirtualObjectToScene(model)
        }
        
        let failure = { [weak self] (error: WayfairModelError) -> Void in
            self?.failedToLoadWayfairModel(error)
        }
        
        virtualObjectLoader.loadWayfairModel(forSKU: sku, successHandler: success, failureHandler: failure)
    }
    
    private func failedToLoadWayfairModel(_ error: WayfairModelError) {
        let alert = UIAlertController(title: "Failed to load Wayfair model", message: error.errorDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    /// Determines if the tap gesture for presenting the `VirtualObjectSelectionViewController` should be used.
    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        return virtualObjectLoader.loadedObjects.isEmpty
    }
    
    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        return true
    }
    
    /// - Tag: restartExperience
    func restartExperience() {
        guard isRestartAvailable, !virtualObjectLoader.isLoading else { return }
        isRestartAvailable = false

        statusViewController.cancelAllScheduledMessages()

        virtualObjectLoader.removeAllVirtualObjects()
        addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
        addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])

        resetTracking()

        // Disable restart for a while in order to give the session time to restart.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.isRestartAvailable = true
        }
    }
}
