//
//  ShadowUploadDelegate.swift
//  ShadowUploadModule
//
//  Created by Joshua Nicholl on 31/3/21.
//

import Foundation


class ShadowUploadDelegate: NSObject, URLSessionDataDelegate {
    private let storageFile = "events.json"
    
    private var latestTaskEvents: [String: [String: String]]!
    private var responseBodies: [String: Data] = [:]
    
    private weak var bridgeModule: ShadowUploadModule?
    
    override init() {
        super.init()
        let fileManager = FileManager.default
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            latestTaskEvents = [:]
            return
        }
        let fileURL = dir.appendingPathComponent(storageFile)
        if !fileManager.fileExists(atPath: fileURL.absoluteString) {
            latestTaskEvents = [:]
            return
        }
        do {
            latestTaskEvents = try (JSONDecoder().decode(Dictionary<String, [String: String]>.self, from: Data(contentsOf: fileURL)))
        } catch {
            tryLog(error: error.localizedDescription)
            latestTaskEvents = [:]
        }
    }
    
    deinit {
        saveLoaded()
    }
    
    //MARK: Class Utilities
    private func tryLog(error str: String) {
        if bridgeModule != nil {
            RCTLogError(str)
        }
    }
    
    private func saveLoaded() {
        let fileManager = FileManager.default
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let fileURL = dir.appendingPathComponent(storageFile)
        do {
            try JSONEncoder().encode(self.latestTaskEvents).write(to: fileURL, options: .atomicWrite)
        } catch {
            tryLog(error: error.localizedDescription)
        }
    }
    
    private func extractResponse(forTask ID: String) -> String? {
        guard let responseData = responseBodies.removeValue(forKey: ID) else { return nil }
        return String(data: responseData, encoding: .utf8)
    }

    private func extractSavedEvent(forTask ID: String) -> [String: String]? {
        return latestTaskEvents.removeValue(forKey: ID)
    }
    
    //MARK: Bridge Communication Utilities
    private func tryEmit(event: String, data: inout [String: String], ID: String) -> Void {
        if let bridgeModule = self.bridgeModule, bridgeModule.sendUploadUpdate(eventName: "ShadowUpload-\(event)", body: data) {
            return
        }
        data.updateValue(event, forKey: "eventType")
        self.latestTaskEvents.updateValue(data, forKey: ID)
    }
    
    func getLatest(requestedEvents: inout [String: [String: String]?]) {
        requestedEvents.keys.forEach({ID in
            requestedEvents[ID] = self.extractSavedEvent(forTask: ID)
        });
        self.saveLoaded()
    }
    
    func assignBridgeModule(_ module: ShadowUploadModule) {
        self.bridgeModule = module
    }
    
    //MARK: URLSessionDataDelegate implementations
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ID = task.taskDescription else {
            return;
        }
        var hadRequestError = false
        var data: [String: String] = ["ID": ID]
        if let response = task.response as? HTTPURLResponse,
           let storedData = extractResponse(forTask: ID) {
            hadRequestError = response.statusCode >= 300
            data.updateValue("\(response.statusCode)", forKey: "status")
            data.updateValue(storedData, forKey: "body")
        }
        var event : String!
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
        var data: [String: String] = [
            "ID": ID,
            "bytesSent": "\(totalBytesSent)"
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
