
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
  onCancelled?(ev: NativeCancelledEvent): void;
  onCompleted?(ev: NativeCompletedEvent): void;
  onError?(ev: NativeErrorEvent): void;
  onProgress?(ev: NativeProgressEvent): void;
}