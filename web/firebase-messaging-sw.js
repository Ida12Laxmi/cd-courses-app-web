importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: 'AIzaSyDXylbEFhw-V2Lw3r405coDlsLLxw7k1kw',
  authDomain: 'clickdigitals-courses-app.firebaseapp.com',
  projectId:'clickdigitals-courses-app',
  storageBucket: 'clickdigitals-courses-app.firebasestorage.app',
  messagingSenderId:  '60779357539',
  appId:'1:60779357539:web:c75c6d55907c949e9e9f56',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? "Notification";
  self.registration.showNotification(title, {
    body: payload.notification?.body,
    icon: "/icons/Icon-192.png",
  });
});