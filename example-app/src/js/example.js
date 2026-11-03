import { LocalGeofence } from 'capacitor-local-geofence';

const output = (value) => {
  document.getElementById('output').textContent = JSON.stringify(value, null, 2);
};

LocalGeofence.addListener('transition', (event) => output({ live: event }));

window.requestForeground = async () => output(await LocalGeofence.requestPermissions());

window.requestBackground = async () =>
  output(await LocalGeofence.requestPermissions({ permissions: ['backgroundLocation'] }));

window.addHere = () => {
  navigator.geolocation.getCurrentPosition(async ({ coords }) => {
    try {
      await LocalGeofence.addRegion({
        id: 'test',
        latitude: coords.latitude,
        longitude: coords.longitude,
        radius: 150,
        enterNotification: { title: 'Arrived', body: 'Entered at {time}' },
        exitNotification: { title: 'Left', body: 'Left at {time}' },
      });
      output(await LocalGeofence.getRegions());
    } catch (error) {
      output({ error: error.message });
    }
  }, (error) => output({ error: error.message }));
};

window.showEvents = async () => output(await LocalGeofence.getEvents());

window.clearAll = async () => {
  await LocalGeofence.clearEvents();
  output(await LocalGeofence.getEvents());
};
