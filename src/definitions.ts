import type { PermissionState, PluginListenerHandle } from '@capacitor/core';

export type LocalGeofencePermissionType = 'location' | 'backgroundLocation' | 'notifications';

export interface PermissionStatus {
  /**
   * Location while the app is in use (Android: fine/coarse location, iOS: "when in use" or "always").
   *
   * @since 0.1.0
   */
  location: PermissionState;
  /**
   * Location while the app is closed (Android: `ACCESS_BACKGROUND_LOCATION`, iOS: "always").
   * Required for geofence events while the app is not running.
   *
   * @since 0.1.0
   */
  backgroundLocation: PermissionState;
  /**
   * Permission to show the native transition notifications.
   *
   * @since 0.1.0
   */
  notifications: PermissionState;
}

export interface RequestPermissionsOptions {
  /**
   * Permissions to request. Request `location` before `backgroundLocation`:
   * Android 11+ and iOS only grant background location as an upgrade of foreground location.
   *
   * @default ['location', 'notifications']
   * @since 0.1.0
   */
  permissions?: LocalGeofencePermissionType[];
}

export interface TransitionNotification {
  /**
   * Notification title. `{time}` is replaced with the local time of the transition (e.g. `17:42`).
   *
   * @since 0.1.0
   */
  title: string;
  /**
   * Notification body. `{time}` is replaced with the local time of the transition.
   *
   * @since 0.1.0
   */
  body: string;
}

export interface Region {
  /**
   * Unique identifier. Adding a region with an existing id replaces it.
   *
   * @since 0.1.0
   */
  id: string;
  /**
   * @since 0.1.0
   */
  latitude: number;
  /**
   * @since 0.1.0
   */
  longitude: number;
  /**
   * Radius in meters. Values below ~100 m trigger unreliably on both platforms.
   *
   * @since 0.1.0
   */
  radius: number;
  /**
   * Record enter transitions.
   *
   * @default true
   * @since 0.1.0
   */
  notifyOnEnter?: boolean;
  /**
   * Record exit transitions.
   *
   * @default true
   * @since 0.1.0
   */
  notifyOnExit?: boolean;
  /**
   * Native notification shown on enter. Omit to record the event silently.
   *
   * @since 0.1.0
   */
  enterNotification?: TransitionNotification;
  /**
   * Native notification shown on exit. Omit to record the event silently.
   *
   * @since 0.1.0
   */
  exitNotification?: TransitionNotification;
  /**
   * Android only: drawable resource name for the notification small icon (e.g. `ic_stat_geofence`).
   * Falls back to the app icon.
   *
   * @since 0.1.0
   */
  androidSmallIcon?: string;
}

export type Transition = 'enter' | 'exit';

export interface TransitionEvent {
  /**
   * Unique event id, use it with `clearEvents`.
   *
   * @since 0.1.0
   */
  id: string;
  /**
   * @since 0.1.0
   */
  regionId: string;
  /**
   * @since 0.1.0
   */
  transition: Transition;
  /**
   * Time of the transition in milliseconds since epoch
   * (Android: time of the triggering location, iOS: time of delivery).
   *
   * @since 0.1.0
   */
  timestamp: number;
}

export interface LocalGeofencePlugin {
  /**
   * @since 0.1.0
   */
  checkPermissions(): Promise<PermissionStatus>;

  /**
   * @since 0.1.0
   */
  requestPermissions(options?: RequestPermissionsOptions): Promise<PermissionStatus>;

  /**
   * Start monitoring a circular region. Regions persist across app restarts and device reboots.
   * iOS monitors at most 20 regions per app.
   *
   * @since 0.1.0
   */
  addRegion(options: Region): Promise<void>;

  /**
   * @since 0.1.0
   */
  removeRegion(options: { id: string }): Promise<void>;

  /**
   * @since 0.1.0
   */
  getRegions(): Promise<{ regions: Region[] }>;

  /**
   * All recorded transitions, oldest first, including those that happened while the app was closed.
   * Events stay stored until `clearEvents` is called (at most the newest 500).
   *
   * @since 0.1.0
   */
  getEvents(): Promise<{ events: TransitionEvent[] }>;

  /**
   * Delete recorded events. Without `ids` all events are deleted.
   *
   * @since 0.1.0
   */
  clearEvents(options?: { ids?: string[] }): Promise<void>;

  /**
   * Called for each transition while the app is running. The event is stored as well,
   * so `getEvents` still returns it.
   *
   * @since 0.1.0
   */
  addListener(eventName: 'transition', listenerFunc: (event: TransitionEvent) => void): Promise<PluginListenerHandle>;

  /**
   * @since 0.1.0
   */
  removeAllListeners(): Promise<void>;
}
