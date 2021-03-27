import Foundation

class ShadowUploadDataDelegate: NSObject, URLSessionDataDelegate {
    private weak var bridgeModule: ShadowUploadModule?;
    private var latestTaskEvents: [String: [String: Any]] = [:]
    private var responseBodies: [String: Data] = [:]
    
    //MARK: Class Utilities
    private func extractResponse(forTask ID: String) -> String? {
        guard let responseData = responseBodies[ID] else {
            return nil
        }
        responseBodies.removeValue(forKey: ID)
        guard let response = String(data: responseData, encoding: .utf8) else {
            return nil
        }
        return response
    }

    private func extractEvent(forTask ID: String) -> [String: Any]? {
        guard let event = latestTaskEvents[ID] else {
            return nil
        }
        latestTaskEvents[ID]?.removeValue(forKey: ID)
        return event
    }
    
    //MARK: Bridge Communication Utilities
    private func tryEmit(event: String, data: inout [String: Any], ID: String) -> Void {
        if let bridgeModule = self.bridgeModule {
            if bridgeModule.sendUploadUpdate(eventName: "ShadowUpload-\(event)", body: data) { return; }
        }
        data.updateValue(event, forKey: "eventType")
        self.latestTaskEvents.updateValue(data, forKey: ID)
    }
    
    func getLatest(requestedEvents: inout [String: [String: Any]?]) {
        requestedEvents.keys.forEach({ID in
            requestedEvents[ID] = self.extractEvent(forTask: ID)
        });
        
    }
    
    func assignBridgeModule(module: ShadowUploadModule) {
        self.bridgeModule = module
    }
    
    //MARK: URLSessionDataDelegate implementations
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ID = task.taskDescription else {
            return;
        }
        var hadRequestError = false
        var data: [String: Any] = ["ID": ID]
        if let response : HTTPURLResponse = task.response as? HTTPURLResponse {
            hadRequestError = response.statusCode >= 300
            data.updateValue(response.statusCode, forKey: "status")
            if let storedData = extractResponse(forTask: ID) {
                data.updateValue(storedData, forKey: "body")
            }
        }
        var event : String = "";
        if(error == nil && !hadRequestError){
            event = "completed"
        } else if let err = error as NSError? {
            event = (err.code == NSURLErrorCancelled ? "cancelled" : "error")
            data.updateValue(err.localizedDescription, forKey: "error")
        }
        self.tryEmit(event: event, data: &data, ID: ID)
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let ID = task.taskDescription else { return }
        var data: [String: Any] = [
            "ID": ID,
            "bytesSent": totalBytesSent
        ];
        self.tryEmit(event: "progress", data: &data, ID: ID)
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let handler = ShadowUploadManager.getCompletionHandler() else {
            return;
        }
        DispatchQueue.main.async {
            handler();
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: (URLSession.ResponseDisposition) -> Void) {
        if let ID = dataTask.taskDescription {
            responseBodies.updateValue(Data(), forKey: ID)
        }
        return completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let ID = dataTask.taskDescription else { return }
        if responseBodies[ID] == nil {
            responseBodies.updateValue(Data(), forKey: ID)
        }
        responseBodies[ID]!.append(data)
    }
}

@objc(ShadowUploadModule)
class ShadowUploadModule: RCTEventEmitter {
    var hasListeners = false
    
    override init() {
        super.init()
        if(!ShadowUploadManager.sessionExists()){
            let delegate = ShadowUploadDataDelegate();
            delegate.assignBridgeModule(module: self)
            ShadowUploadManager.createSession(delegate)
        } else if let delegate = ShadowUploadManager.getDelegate() as? ShadowUploadDataDelegate {
            delegate.assignBridgeModule(module: self)
        }
    }
    
    deinit {
        RCTLogInfo("Deallocating ShadowUploadModule")
    }
    
    
    
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
    
    public func sendUploadUpdate(eventName: String, body: [String: Any]) -> Bool {
        if hasListeners {
            self.sendEvent(withName: eventName, body: body)
            return true;
        }
        return false;
    }
    
    //MARK: - Native Methods
    
    @objc(startUpload:withResolver:withRejecter:)
    func startUpload(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
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
            return reject("Error", "Upload URL is invalid, you need to encode it or you have not added a URI protocol prefix", nil)
        }
        guard let mediaStorageLocation = URL(string:fileURI) else {
            return reject("Error", "Storage location is invalid, you need to encode it or you have not added a URI protocol prefix", nil)
        }
        var request: URLRequest = URLRequest(url:requestURL)
        request.httpMethod = method
        for entry in headers {
            if(entry.value is Int){
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
        var out: [String: [String: Any]?] = [:]
        tasks.forEach({str in out[str] = nil })
        (ShadowUploadManager.getDelegate() as? ShadowUploadDataDelegate)?.getLatest(requestedEvents: &out)
        resolve(out)
    }
}

