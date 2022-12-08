import { NativeModules, NativeEventEmitter, EmitterSubscription } from 'react-native';

const { BGUploadModule } = NativeModules
const emitter = new NativeEventEmitter(BGUploadModule);


const eventPrefix = 'BGUpload-';

export type UploadEvent = 'progress' | 'error' | 'completed' | 'cancelled';

export interface UploadOptions {
  headers?: Object;
  ID: string;
  method?: 'PUT' | 'POST';
  path: string;
  url: string;
};

interface NativeCancelledEvent {
  ID: string;
}

interface NativeCompletedEvent {
  ID: string;
  body: any;
  status: number;
}

interface NativeErrorEvent {
  ID: string;
  body?: any;
  error: string;
  status?: number;
}

interface NativeProgressEvent {
  ID: string;
  bytesSent: number;
}

export interface IUploadSubscriber {
  onCancelled?(ev: NativeCancelledEvent): any;
  onCompleted?(ev: NativeCompletedEvent): any;
  onError?(ev: NativeErrorEvent): any;
  onProgress?(ev: NativeProgressEvent): any;
}

export type NativeUploadEvent = NativeCancelledEvent | NativeCompletedEvent | NativeErrorEvent | NativeProgressEvent;

const eventTypes : UploadEvent[] = ["progress", "cancelled", "error", "completed"];

class Uploader {
  _nativeSubscriptions: EmitterSubscription[] = [];
  _subscribers: Map<String, IUploadSubscriber[]> = new Map<String, IUploadSubscriber[]>();
  private static instance: Uploader | null = null

  private constructor(){ }

  static getInstance() {
    if(!this.instance) {
      this.instance = new Uploader();
    }
    return this.instance;
  }

  async _callEventHandlerForID<EventType extends UploadEvent>(eventType: EventType, data: NativeUploadEvent) {
    const subs = this._subscribers.get(data.ID);
    if(!subs) return;
    subs.forEach(sub => {
      switch(eventType) {
      case "cancelled":
        sub.onCancelled?.(data as NativeCancelledEvent);
        break;
      case "completed":
        sub.onCompleted?.(data as NativeCompletedEvent);
        break;
      case "error":
        sub.onError?.(data as NativeErrorEvent);
        break;
      case "progress":
        sub.onProgress?.(data as NativeProgressEvent);
        break;
      }
    });
  }

  subscribe(id: string, sub: IUploadSubscriber) {
    const shouldStartListening = !this._nativeSubscriptions.length;
    const existingSubs = this._subscribers.get(id);
    if(!existingSubs) {
      this._subscribers.set(id, [sub]);
    } else {
      this._subscribers.set(id, [...existingSubs, sub]);
    }
    if(shouldStartListening) {
      this._nativeSubscriptions = this._startNativeListening();
    }
    return () => {
      this._unsubscribe(id, sub);
    };
  }

  _unsubscribe(id: string, sub: IUploadSubscriber) {
    const oldSubs = this._subscribers.get(id);
    if(oldSubs) {
      const newSubs = oldSubs.filter(s => sub !== s);
      if(!newSubs.length) {
        this._subscribers.delete(id);
      } else {
        this._subscribers.set(id, newSubs);
      }
    }
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
      subs.push(emitter.addListener(eventPrefix + type, (data: NativeUploadEvent) => this._callEventHandlerForID(type, data), this));
    }
    return subs;
  }

  startUpload(options: UploadOptions): Promise<string> {
    return BGUploadModule.startUpload(options);
  }

  async retrieveLastEvents(taskIDs: string[]) : Promise<{ [id: string]: NativeUploadEvent | undefined }> {
    return BGUploadModule.retrieveEvents(taskIDs);
  }
}

export default Uploader.getInstance();
