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
  handleEvent: (data: NativeEventData | undefined) => void;
}

export interface NativeEventData {
  //Common
  ID: string;
  //Completed, cancelled and error
  status?: number; 
  body?: any
  error?: string; 
  //Progress
  bytesSent?: number;
  //Retrieving saved events, check this value when checking what to do with the event
  eventType?: UploadEvent
}
const eventTypes : UploadEvent[] = ["progress", "cancelled", "error", "completed"];

class Uploader {
  _nativeSubscriptions: EmitterSubscription[] = [];
  _subscribers: Map<String, IUploadSubscriber> = new Map<String, IUploadSubscriber>();
  

  async _callEventHandlerForID(eventType: UploadEvent, data: NativeEventData) {
    const sub = this._subscribers.get(data.ID);
    if(!sub) return;
    data.eventType = eventType;
    sub.handleEvent(data);
    if(eventType !== "progress"){
      this._unsubscribe(data.ID);
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
      subs.push(emitter.addListener(eventPrefix + type, (data: NativeEventData) => this._callEventHandlerForID(type, data), this));
    }
    return subs;
  }

  startUpload(options: UploadOptions): Promise<string> {
    return HightroUploadService.startUpload(options);
  }

  async retrieveLastEvents() : Promise<{ [id: string]: NativeEventData | undefined }> {
    return HightroUploadService.retrieveEvents();
  }
}

export default new Uploader();
