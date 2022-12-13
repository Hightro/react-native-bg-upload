//
//  BGUploadDelegate.swift
//  BGUploadModule
//
//  Created by Joshua Nicholl on 31/3/21.
//

import Foundation


class BGUploadDelegate: NSObject, URLSessionDataDelegate {
    private let storageFile = "events.json"
    
    private var latestTaskEvents: [String: [String: String]] = [:]
    private var responseBodies: [String: Data] = [:]
    
    private weak var bridgeModule: BGUploadModule?
    
    override init() {
        super.init()
        let fileManager = FileManager.default
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let fileURL = dir.appendingPathComponent(storageFile)
        if !fileManager.fileExists(atPath: fileURL.absoluteString) {
            return
        }
        do {
            let savedEvents = try (JSONDecoder().decode(Dictionary<String, [String: String]>.self, from: Data(contentsOf: fileURL)))
            for (id, event) in savedEvents {
                latestTaskEvents.updateValue(event, forKey: id)
            }
        } catch {
            tryLog(error: error.localizedDescription)
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
        let bridgeModule = self.bridgeModule
        data.updateValue(event, forKey: "eventType")
        self.latestTaskEvents.updateValue(data, forKey: ID)
        bridgeModule.sendUploadUpdate(eventName: "BGUpload-\(event)", body: data)
    }
    
    func getLatest(requestedEvents: inout [String: [String: String]?]) {
        requestedEvents.keys.forEach({ID in
            requestedEvents.updateValue(self.extractSavedEvent(forTask: ID), forKey: ID)
        });
        self.saveLoaded()
    }
    
    func assignBridgeModule(_ module: BGUploadModule) {
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
        } else {
            event = "error"
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
        guard let handler = BGUploadManager.getCompletionHandler() else {
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
