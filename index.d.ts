declare type UploadEvent = 'progress' | 'error' | 'completed' | 'cancelled';

declare interface UploadOptions {
  url: string;
  path: string;
  method?: 'PUT' | 'POST';
  ID: string;
  headers?: Object;
};

declare interface IUploadSubscriber {
  onNativeError: (error: string ) => void;
  onNativeCancelled: () => void;
  onNativeProgress: (sent: number) => void;
  onNativeCompleted: (status: number) => void;
}
