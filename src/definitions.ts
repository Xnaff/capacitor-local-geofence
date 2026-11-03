export interface LocalGeofencePlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
