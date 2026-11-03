import { WebPlugin } from '@capacitor/core';

import type { LocalGeofencePlugin, PermissionStatus, Region, TransitionEvent } from './definitions';

export class LocalGeofenceWeb extends WebPlugin implements LocalGeofencePlugin {
  async checkPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('Geofencing is not available on web.');
  }

  async requestPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('Geofencing is not available on web.');
  }

  async addRegion(): Promise<void> {
    throw this.unimplemented('Geofencing is not available on web.');
  }

  async removeRegion(): Promise<void> {
    throw this.unimplemented('Geofencing is not available on web.');
  }

  async getRegions(): Promise<{ regions: Region[] }> {
    throw this.unimplemented('Geofencing is not available on web.');
  }

  async getEvents(): Promise<{ events: TransitionEvent[] }> {
    throw this.unimplemented('Geofencing is not available on web.');
  }

  async clearEvents(): Promise<void> {
    throw this.unimplemented('Geofencing is not available on web.');
  }
}
