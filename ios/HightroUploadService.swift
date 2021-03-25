import Foundation

class HightroDataDelegate: NSObject, URLSessionDataDelegate {
    private weak var bridgeModule: HightroUploadService?;
    private var latestTaskEvents: [String: [String: Any]] = [:]
    private var responseBodies: [String: Data] = [:]
    
    //MARK: Class Utilities
    private func extractResponse(forTask ID: String) -> String? {
        guard let responseData = responseBodies[ID] else {
            return nil
        }
        responseBodies.removeValue(forKey: ID)
        guard let response = String(data: responseData, encoding: .utf16) else {
            return nil
        }
        return response
    }
    
    //MARK: Bridge Communication Utilities
    private func tryEmit(event: String, data: [String: Any], ID: String) -> Void {
        var mutableData = data;
        if let bridgeModule = self.bridgeModule {
            if bridgeModule.sendUploadUpdate(eventName: event, body: data) { return; }
        }
        RCTLog("Could not emit, storing to dictionary.");
        mutableData.updateValue(event, forKey: "eventType")
        self.latestTaskEvents.updateValue(data, forKey: ID)
    }
    
    func getLatest() -> [String: [String: Any]] {
        let oldEvents = self.latestTaskEvents
        self.latestTaskEvents = [:]
        return oldEvents
    }
    
    func assignBridgeModule(module: HightroUploadService) {
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
        var event : String = "HightroUploadService-";
        if(error == nil && !hadRequestError){
            event.append("completed");
        } else if let err = error as NSError? {
            RCTLogInfo(err.code == NSURLErrorCancelled ? "Task with ID \(ID) was cancelled, possibly due to the user force closing the app while in progress." : err.localizedDescription)
            event.append(err.code == NSURLErrorCancelled ? "cancelled" : "error")
            data.updateValue(err.localizedDescription, forKey: "error")
        }
        self.tryEmit(event: event, data: data, ID: ID)
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let ID = task.taskDescription else { return }
        let eventName = "HightroUploadService-progress";
        let data: Dictionary<String, Any> = [
            "ID": ID,
            "bytesSent": totalBytesSent
        ];
        self.tryEmit(event: eventName, data: data, ID: ID)
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let handler = HightroSessionManager.getCompletionHandler() else {
            return;
        }
        DispatchQueue.main.async {
            handler();
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
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
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        //TODO: Implement CoreData storage of saved events
    }
}

@objc(HightroUploadService)
class HightroUploadService: RCTEventEmitter {
    var hasListeners = false
    
    override init() {
        super.init()
        if(!HightroSessionManager.sessionExists()){
            let delegate = HightroDataDelegate();
            delegate.assignBridgeModule(module: self)
            HightroSessionManager.createSession(delegate)
        } else if let delegate = HightroSessionManager.getDelegate() as? HightroDataDelegate {
            delegate.assignBridgeModule(module: self)
        }
    }
    
    deinit {
        RCTLogInfo("Deallocating HightroUploadService module")
    }
    
    @objc override func supportedEvents() -> [String]! {
        return [
            "HightroUploadService-progress",
            "HightroUploadService-cancelled",
            "HightroUploadService-error",
            "HightroUploadService-completed"
        ]
    }
    
    @objc override class func requiresMainQueueSetup() -> Bool {
        return false
    }
    
    @objc override func startObserving() {
        hasListeners = true;
    }

    @objc override func stopObserving() {
        hasListeners = false;
    }
    
    @objc override func invalidate() {
        RCTLogInfo("Invalidating HightroUploadService module")
    }
    
    public func sendUploadUpdate(eventName: String, body: Dictionary<String, Any>) -> Bool {
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
        guard let headers = options["headers"] as? Dictionary<String, Any> else { return incorrectOptionFormat("headers") }
        
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
        if (!HightroSessionManager.createTask(with: request, withFilePath: mediaStorageLocation, withID: ID)) {
            return reject("Error", "Target NSURLSession does not exist, please open an issue on GitHub if this occurs.", nil)
        }
        
        return resolve(nil)
    }
    
    @objc(retrieveEvents:withResolver:withRejecter:)
    func retrieveEvents(forTasks tasks: [String], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        let savedEvents = (HightroSessionManager.getDelegate() as? HightroDataDelegate)?.getLatest()
        var forJS: [[String: Any]?] = []
        tasks.forEach({body in forJS.append(savedEvents?[body]) })
        resolve(forJS)
    }
}

