import Foundation

@objc(ShadowUploadModule)
class ShadowUploadModule: RCTEventEmitter {
    var hasListeners = false
    
    override init() {
        super.init()
        if(!ShadowUploadManager.sessionExists()){
            let delegate = ShadowUploadDelegate();
            delegate.assignBridgeModule(self)
            ShadowUploadManager.createSession(delegate)
        } else if let delegate = ShadowUploadManager.getDelegate() as? ShadowUploadDelegate {
            delegate.assignBridgeModule(self)
        }
    }
    
    deinit {
        RCTLogInfo("Deallocating ShadowUploadModule")
    }
    //MARK: Class Utilities
    public func sendUploadUpdate(eventName: String, body: [String: Any]) -> Bool {
        if hasListeners {
            self.sendEvent(withName: eventName, body: body)
            return true;
        }
        return false;
    }
    
    //MARK: RCTBridgeModule overrides
    @objc override func supportedEvents() -> [String]! {
        return [
            "ShadowUpload-progress",
            "ShadowUpload-cancelled",
            "ShadowUpload-error",
            "ShadowUpload-completed"
        ]
    }
    
    @objc override class func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc override func startObserving() {
        hasListeners = true;
    }

    @objc override func stopObserving() {
        hasListeners = false;
    }
    
    @objc override func invalidate() {
        RCTLogInfo("Invalidating ShadowUploadModule")
    }
    
    //MARK: Native Module Methods
    @objc(startUploadWithOptions:withResolver:withRejecter:)
    func startUpload(withOptions options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
        let incorrectOptionFormat: (_: String) -> Void = {paramName in
            let expectedType = paramName != "headers" ? "a string" : "an object with type { [header: string]: string | number }";
            return reject("Error", "Option '\(paramName)' must be \(expectedType)", nil)
        }
        guard let uploadURL = options["url"] as? String else { return incorrectOptionFormat("url") }
        guard let fileURI = options["path"] as? String else { return incorrectOptionFormat("path") }
        guard let method = options["method"] as? String else { return incorrectOptionFormat("method") }
        guard let ID = options["ID"] as? String else { return incorrectOptionFormat("ID") }
        guard let headers = options["headers"] as? [String: Any] else { return incorrectOptionFormat("headers") }
        
        guard let requestURL = URL(string: uploadURL) else {
            return reject("Error", "Upload URL is invalid, you may not have added a URI protocol prefix", nil)
        }
        guard let mediaStorageLocation = URL(string:fileURI) else {
            return reject("Error", "Storage location is invalid, you may not have added a URI protocol prefix", nil)
        }
        var request: URLRequest = URLRequest(url:requestURL)
        request.httpMethod = method
        for entry in headers {
            if entry.value is Int {
                let val = String(entry.value as! Int)
                request.setValue(val, forHTTPHeaderField: entry.key)
            } else if entry.value is String {
                let val = entry.value as! String
                request.setValue(val, forHTTPHeaderField: entry.key)
            }
        }
        if (!ShadowUploadManager.createTask(with: request, withFilePath: mediaStorageLocation, withID: ID)) {
            return reject("Error", "Target NSURLSession does not exist.", nil)
        }
        
        return resolve(nil)
    }
    
    @objc(retrieveEventsForTasks:withResolver:withRejecter:)
    func retrieveEvents(forTasks tasks: [String], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        var out: [String: [String: String]?] = [:]
        tasks.forEach({str in out[str] = nil })
        (ShadowUploadManager.getDelegate() as? ShadowUploadDelegate)?.getLatest(requestedEvents: &out)
        resolve(out)
    }
}

