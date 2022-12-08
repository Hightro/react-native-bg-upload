
declare type UploadEvent = "progress" | "error" | "completed" | "cancelled";

declare interface UploadOptions {
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

declare interface IUploadSubscriber {
  onCancelled?(ev: NativeCancelledEvent): any;
  onCompleted?(ev: NativeCompletedEvent): any;
  onError?(ev: NativeErrorEvent): any;
  onProgress?(ev: NativeProgressEvent): any;
}