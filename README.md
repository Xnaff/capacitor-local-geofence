# capacitor-local-geofence

Server-free geofencing for Capacitor: enter/exit events persisted on device with timestamps and native local notifications, even when the app is closed.

## Install

To use npm

```bash
npm install capacitor-local-geofence
````

To use yarn

```bash
yarn add capacitor-local-geofence
```

Sync native files

```bash
npx cap sync
```

## Why

Most geofencing plugins either need a paid licence or deliver background events only to a web server.
This plugin keeps everything on the device:

- Enter/exit events are **persisted natively with a timestamp**, also when the app is closed or was killed.
- An optional **native local notification** is shown per transition (`{time}` placeholder for the local time).
- The app reads the stored events with `getEvents()` the next time it runs, or live via the `transition` listener.
- Regions survive app restarts, device reboots and app updates.

No server, no account, no licence key.

## Platform setup

### iOS

Add to `ios/App/App/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to detect when you arrive at or leave your saved places.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Used to detect when you arrive at or leave your saved places, also while the app is closed.</string>
```

No background mode is required: region monitoring relaunches the app in the background for each transition.
iOS monitors at most 20 regions per app. Radii above the device's `maximumRegionMonitoringDistance` are rejected.
Events while the app is closed need **Background App Refresh** enabled for the app, the "Always" permission and
**precise location** (with approximate location `location` reports `denied` and `addRegion` rejects).

Recreate the region monitor at launch so events that relaunch a closed app are not missed before the
Capacitor bridge has loaded. In `ios/App/App/AppDelegate.swift`:

```swift
import LocalGeofencePlugin        // CocoaPods projects: import CapacitorLocalGeofence

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    _ = LocalGeofence.shared
    return true
}
```

The plugin ships a privacy manifest (`PrivacyInfo.xcprivacy`) declaring its UserDefaults use (reason `CA92.1`).

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

The plugin declares `RECEIVE_BOOT_COMPLETED` and its receivers itself. It uses Google Play services
(`com.google.android.gms:play-services-location`, override the version with `playServicesLocationVersion`
in `android/variables.gradle`). Devices without Play services cannot geofence.

Fine location is required; coarse-only location reports `location: 'denied'`.

## Usage

```typescript
import { LocalGeofence } from 'capacitor-local-geofence';

// Foreground location first, then the background upgrade (Android 11+ and iOS require this order).
await LocalGeofence.requestPermissions({ permissions: ['location', 'notifications'] });
await LocalGeofence.requestPermissions({ permissions: ['backgroundLocation'] });

await LocalGeofence.addRegion({
  id: 'office',
  latitude: 52.52,
  longitude: 13.405,
  radius: 150,
  exitNotification: { title: 'Left the office', body: 'Stop the timer at {time}?' },
});

// On app start / resume: process what happened while the app was closed.
const { events } = await LocalGeofence.getEvents();
for (const event of events) {
  console.log(event.regionId, event.transition, new Date(event.timestamp));
}
await LocalGeofence.clearEvents({ ids: events.map((e) => e.id) });
```

### Behaviour notes

- Adding a region while already inside it records no event on Android; iOS may deliver an immediate `enter`.
- A repeated identical transition for the same region (e.g. two `exit` in a row) is dropped.
- Geofence accuracy depends on the OS: expect 100–200 m jitter and delays of a few minutes, especially on Android.
- Android timestamps come from the triggering location, iOS timestamps from the moment of delivery.
- At most the newest 500 events are kept.
- Notifications are meant for the background. While the app is in the foreground iOS shows them only if
  another plugin (e.g. `@capacitor/local-notifications` with `presentationOptions`) presents notifications;
  use the `transition` listener in the foreground instead.
- Android re-adds regions after reboot, app update, location being turned back on (not delivered on every
  Android version), with background retries after a geofencing outage, and on every app resume.

## API

<docgen-index>

* [`checkPermissions()`](#checkpermissions)
* [`requestPermissions(...)`](#requestpermissions)
* [`addRegion(...)`](#addregion)
* [`removeRegion(...)`](#removeregion)
* [`getRegions()`](#getregions)
* [`getEvents()`](#getevents)
* [`clearEvents(...)`](#clearevents)
* [`addListener('transition', ...)`](#addlistenertransition-)
* [`removeAllListeners()`](#removealllisteners)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### checkPermissions()

```typescript
checkPermissions() => Promise<PermissionStatus>
```

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

**Since:** 0.1.0

--------------------


### requestPermissions(...)

```typescript
requestPermissions(options?: RequestPermissionsOptions | undefined) => Promise<PermissionStatus>
```

| Param         | Type                                                                            |
| ------------- | ------------------------------------------------------------------------------- |
| **`options`** | <code><a href="#requestpermissionsoptions">RequestPermissionsOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

**Since:** 0.1.0

--------------------


### addRegion(...)

```typescript
addRegion(options: Region) => Promise<void>
```

Start monitoring a circular region. Regions persist across app restarts and device reboots.
iOS monitors at most 20 regions per app.

| Param         | Type                                      |
| ------------- | ----------------------------------------- |
| **`options`** | <code><a href="#region">Region</a></code> |

**Since:** 0.1.0

--------------------


### removeRegion(...)

```typescript
removeRegion(options: { id: string; }) => Promise<void>
```

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Since:** 0.1.0

--------------------


### getRegions()

```typescript
getRegions() => Promise<{ regions: Region[]; }>
```

**Returns:** <code>Promise&lt;{ regions: Region[]; }&gt;</code>

**Since:** 0.1.0

--------------------


### getEvents()

```typescript
getEvents() => Promise<{ events: TransitionEvent[]; }>
```

All recorded transitions, oldest first, including those that happened while the app was closed.
Events stay stored until `clearEvents` is called (at most the newest 500).

**Returns:** <code>Promise&lt;{ events: TransitionEvent[]; }&gt;</code>

**Since:** 0.1.0

--------------------


### clearEvents(...)

```typescript
clearEvents(options?: { ids?: string[] | undefined; } | undefined) => Promise<void>
```

Delete recorded events. Without `ids` all events are deleted.

| Param         | Type                             |
| ------------- | -------------------------------- |
| **`options`** | <code>{ ids?: string[]; }</code> |

**Since:** 0.1.0

--------------------


### addListener('transition', ...)

```typescript
addListener(eventName: 'transition', listenerFunc: (event: TransitionEvent) => void) => Promise<PluginListenerHandle>
```

Called for each transition while the app is running. The event is stored as well,
so `getEvents` still returns it.

| Param              | Type                                                                            |
| ------------------ | ------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'transition'</code>                                                       |
| **`listenerFunc`** | <code>(event: <a href="#transitionevent">TransitionEvent</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 0.1.0

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

**Since:** 0.1.0

--------------------


### Interfaces


#### PermissionStatus

| Prop                     | Type                                                        | Description                                                                                                                                         | Since |
| ------------------------ | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| **`location`**           | <code><a href="#permissionstate">PermissionState</a></code> | Location while the app is in use (Android: fine/coarse location, iOS: "when in use" or "always").                                                   | 0.1.0 |
| **`backgroundLocation`** | <code><a href="#permissionstate">PermissionState</a></code> | Location while the app is closed (Android: `ACCESS_BACKGROUND_LOCATION`, iOS: "always"). Required for geofence events while the app is not running. | 0.1.0 |
| **`notifications`**      | <code><a href="#permissionstate">PermissionState</a></code> | Permission to show the native transition notifications.                                                                                             | 0.1.0 |


#### RequestPermissionsOptions

| Prop              | Type                                       | Description                                                                                                                                                      | Default                                    | Since |
| ----------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----- |
| **`permissions`** | <code>LocalGeofencePermissionType[]</code> | Permissions to request. Request `location` before `backgroundLocation`: Android 11+ and iOS only grant background location as an upgrade of foreground location. | <code>['location', 'notifications']</code> | 0.1.0 |


#### Region

| Prop                    | Type                                                                      | Description                                                                                                                 | Default           | Since |
| ----------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ----------------- | ----- |
| **`id`**                | <code>string</code>                                                       | Unique identifier. Adding a region with an existing id replaces it.                                                         |                   | 0.1.0 |
| **`latitude`**          | <code>number</code>                                                       |                                                                                                                             |                   | 0.1.0 |
| **`longitude`**         | <code>number</code>                                                       |                                                                                                                             |                   | 0.1.0 |
| **`radius`**            | <code>number</code>                                                       | Radius in meters. Values below ~100 m trigger unreliably on both platforms.                                                 |                   | 0.1.0 |
| **`notifyOnEnter`**     | <code>boolean</code>                                                      | Record enter transitions.                                                                                                   | <code>true</code> | 0.1.0 |
| **`notifyOnExit`**      | <code>boolean</code>                                                      | Record exit transitions.                                                                                                    | <code>true</code> | 0.1.0 |
| **`enterNotification`** | <code><a href="#transitionnotification">TransitionNotification</a></code> | Native notification shown on enter. Omit to record the event silently.                                                      |                   | 0.1.0 |
| **`exitNotification`**  | <code><a href="#transitionnotification">TransitionNotification</a></code> | Native notification shown on exit. Omit to record the event silently.                                                       |                   | 0.1.0 |
| **`androidSmallIcon`**  | <code>string</code>                                                       | Android only: drawable resource name for the notification small icon (e.g. `ic_stat_geofence`). Falls back to the app icon. |                   | 0.1.0 |


#### TransitionNotification

| Prop        | Type                | Description                                                                                    | Since |
| ----------- | ------------------- | ---------------------------------------------------------------------------------------------- | ----- |
| **`title`** | <code>string</code> | Notification title. `{time}` is replaced with the local time of the transition (e.g. `17:42`). | 0.1.0 |
| **`body`**  | <code>string</code> | Notification body. `{time}` is replaced with the local time of the transition.                 | 0.1.0 |


#### TransitionEvent

| Prop             | Type                                              | Description                                                                                                           | Since |
| ---------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ----- |
| **`id`**         | <code>string</code>                               | Unique event id, use it with `clearEvents`.                                                                           | 0.1.0 |
| **`regionId`**   | <code>string</code>                               |                                                                                                                       | 0.1.0 |
| **`transition`** | <code><a href="#transition">Transition</a></code> |                                                                                                                       | 0.1.0 |
| **`timestamp`**  | <code>number</code>                               | Time of the transition in milliseconds since epoch (Android: time of the triggering location, iOS: time of delivery). | 0.1.0 |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


### Type Aliases


#### PermissionState

<code>'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'</code>


#### LocalGeofencePermissionType

<code>'location' | 'backgroundLocation' | 'notifications'</code>


#### Transition

<code>'enter' | 'exit'</code>

</docgen-api>
