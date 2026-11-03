import { LocalGeofence } from 'capacitor-local-geofence';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    LocalGeofence.echo({ value: inputValue })
}
