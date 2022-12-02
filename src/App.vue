<script setup>
// This starter template is using Vue 3 <script setup> SFCs
// Check out https://vuejs.org/api/sfc-script-setup.html#script-setup
import HelloWorld from './components/HelloWorld.vue'

// Import the functions you need from the SDKs you need
import { PushNotifications } from '@capacitor/push-notifications';
// import OneSignal from 'onesignal-cordova-plugin'
//
//
// // Call this function when your app starts
// function OneSignalInit() {
//   // Uncomment to set OneSignal device logging to VERBOSE
//   // OneSignal.setLogLevel(6, 0);
//
//   // NOTE: Update the setAppId value below with your OneSignal AppId.
//   OneSignal.setAppId();
//   OneSignal.setNotificationOpenedHandler(function(jsonData) {
//     console.log('notificationOpenedCallback: ' + JSON.stringify(jsonData));
//   });
//
//   // Prompts the user for notification permissions.
//   //    * Since this shows a generic native prompt, we recommend instead using an In-App Message to prompt for notification permission (See step 7) to better communicate to your users what notifications they will get.
//   OneSignal.promptForPushNotificationsWithUserResponse(function(accepted) {
//     console.log("User accepted notifications: " + accepted);
//   });
// }

const addListeners = async () => {
  await PushNotifications.addListener('registration', token => {
    console.info('Registration token: ', token.value);
  });

  await PushNotifications.addListener('registrationError', err => {
    console.error('Registration error: ', err.error);
  });

  await PushNotifications.addListener('pushNotificationReceived', notification => {
    console.log('Push notification received: ', notification);
  });

  await PushNotifications.addListener('pushNotificationActionPerformed', notification => {
    console.log('Push notification action performed', notification.actionId, notification.inputValue);
  });
}

const registerNotifications = async () => {

  setTimeout(async () => {

    let permStatus = await PushNotifications.checkPermissions();

    if (permStatus.receive === 'prompt') {
      permStatus = await PushNotifications.requestPermissions();
    }

    if (permStatus.receive !== 'granted') {
      throw new Error('User denied permissions!');
    }
    await PushNotifications.register();
    console.log('register')

  }, 3000)
}
addListeners()
registerNotifications()
const getDeliveredNotifications = async () => {
  const notificationList = await PushNotifications.getDeliveredNotifications();
  console.log('delivered notifications', notificationList);
}
getDeliveredNotifications()
</script>

<template>
  <div>
    <a href="https://vitejs.dev" target="_blank">
      <img src="/vite.svg" class="logo" alt="Vite logo" />
    </a>
    0.0.1
    <a href="https://vuejs.org/" target="_blank">
    </a>
  </div>
  <HelloWorld msg="Vite + Vue" />
</template>

<style scoped>
.logo {
  height: 6em;
  padding: 1.5em;
  will-change: filter;
}
.logo:hover {
  filter: drop-shadow(0 0 2em #646cffaa);
}
.logo.vue:hover {
  filter: drop-shadow(0 0 2em #42b883aa);
}
</style>
