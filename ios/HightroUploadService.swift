import Foundation
import UIKit


class HightroDataDelegate: NSObject, URLSessionDataDelegate {
    public weak var bridgeModule: HightroUploadService?;
    private var latestTaskEvents: [String: [String: Any]] = [:]
    private var responseBodies: [String: Data] = [:]
    
    init (bridgeModule: HightroUploadService) {
        self.bridgeModule = bridgeModule;
    }
    
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
        return self.latestTaskEvents
    }
    
    
    //MARK: URLSessionDataDelegate implementations
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ID = task.taskDescription else {
            return;
        }
        var data: [String: Any] = ["ID": ID]
        let response : HTTPURLResponse = task.response as! HTTPURLResponse
        data.updateValue(response.statusCode, forKey: "status")
        if let storedData = extractResponse(forTask: ID) {
            data.updateValue(storedData, forKey: "body")
        }
        var event : String = "HightroUploadService-";
        if(error == nil && response.statusCode < 300){
            event.append("completed");
        } else if let err = error as NSError? {
            event.append(err.code == NSURLErrorCancelled ? "cancelled" : "error")
            data.updateValue(err.localizedDescription, forKey: "error")
        }
        self.tryEmit(event: event, data: data, ID: ID)
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let eventName = "HightroUploadService-progress";
        let ID = task.taskDescription ?? "";
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
    private var urlSession: URLSession!
    private static let backgroundSessionID = "com.hightro.background";
    
    override init() {
        super.init()
        guard let existingSession = HightroSessionManager.getURLSession() else {
            let delegate = HightroDataDelegate(bridgeModule: self);
            let sessionConfiguration: URLSessionConfiguration = URLSessionConfiguration.background(withIdentifier: HightroUploadService.backgroundSessionID)
            self.urlSession = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
            HightroSessionManager.register(self.urlSession)
            RCTLogInfo("Created new URL session")
            return
        }
        self.urlSession = existingSession
        if let del = self.urlSession.delegate as? HightroDataDelegate {
            del.bridgeModule = self;
            RCTLogInfo("Retrieved existing URL Session with correct delegate.")
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
        RCTLog("Started observing")
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
        let uploadTask: URLSessionUploadTask = self.urlSession.uploadTask(with: request, fromFile: mediaStorageLocation)
        uploadTask.taskDescription = ID
        uploadTask.resume()
        return resolve(nil)
    }
    
    @objc(retrieveEvents:withRejecter:)
    func retrieveEvents(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard let del = self.urlSession.delegate as? HightroDataDelegate else {
            return resolve(nil)
        }
        return resolve(del.getLatest())
    }
}
