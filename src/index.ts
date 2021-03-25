import { NativeModules, NativeEventEmitter, EmitterSubscription } from 'react-native';

const { HightroUploadService } = NativeModules
const emitter = new NativeEventEmitter(HightroUploadService);


const eventPrefix = 'HightroUploadService-';

export type UploadEvent = 'progress' | 'error' | 'completed' | 'cancelled';

export interface UploadOptions {
  url: string;
  path: string;
  method?: 'PUT' | 'POST';
  ID: string;
  headers?: Object;
};

export interface IUploadSubscriber {
  onNativeError: (error: string ) => void;
  onNativeCancelled: () => void;
  onNativeProgress: (sent: number) => void;
  onNativeCompleted: (status: number) => void;
}

interface NativeEventData {
  //Common
  ID: string;
  //Completed, cancelled and error
  status?: number; 
  body?: any
  error?: string; 
  //Progress
  bytesSent?: number;
  //Retrieving saved events, check this value when checking what to do with the event
  eventType?: string
}
const eventTypes : UploadEvent[] = ["progress", "cancelled", "error", "completed"];

class Uploader {
  _nativeSubscriptions: EmitterSubscription[] = [];
  _subscribers: Map<string, IUploadSubscriber> = new Map<string, IUploadSubscriber>();
  

  _callEventHandlerForID(ID: string, eventType: UploadEvent, data: NativeEventData) {
    const sub = this._subscribers.get(ID);
    if(!sub) return;
    switch(eventType){
      case "cancelled":
        sub.onNativeCancelled();
        break;
      case "completed":
        sub.onNativeCompleted(data.status ?? 200);
        break;
      case "error":
        sub.onNativeError(data.error ?? "Error not passed by module.");
        break;
      case "progress":
        sub.onNativeProgress(data.bytesSent ?? 0);
        break;
    }
    if(eventType !== "progress"){
      this._unsubscribe(ID);
    }
  }

  subscribe(id: string, sub: IUploadSubscriber) {
    const shouldStartListening = !this._nativeSubscriptions.length
    this._subscribers.set(id, sub);
    shouldStartListening && this._startNativeListening();
  }

  _unsubscribe(id: string) {
    this._subscribers.delete(id);
    if(this._subscribers.size === 0){
      this._stopNativeListening();
    }
  }

  _stopNativeListening() {
    while(this._nativeSubscriptions.length){
      this._nativeSubscriptions.pop()?.remove();
    }
  }

  _startNativeListening() {
    const subs = [];
    for(const type of eventTypes){
      subs.push(emitter.addListener(eventPrefix + type, (data: NativeEventData) => this._callEventHandlerForID(data.ID, type, data), this));
    }
    return subs;
  }

  startUpload(options: UploadOptions): Promise<string> {
    return HightroUploadService.startUpload(options);
  }

  retrieveLastEvents(targetIDs: string[]) : NativeEventData[] {
    return HightroUploadService.retrieveEvents(targetIDs);
  }
}

export default new Uploader();
