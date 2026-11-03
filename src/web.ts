import { WebPlugin } from '@capacitor/core';

import type { LocalGeofencePlugin } from './definitions';

export class LocalGeofenceWeb extends WebPlugin implements LocalGeofencePlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
