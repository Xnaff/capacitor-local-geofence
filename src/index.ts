import { registerPlugin } from '@capacitor/core';

import type { LocalGeofencePlugin } from './definitions';

const LocalGeofence = registerPlugin<LocalGeofencePlugin>('LocalGeofence', {
  web: () => import('./web').then((m) => new m.LocalGeofenceWeb()),
});

export * from './definitions';
export { LocalGeofence };
