// Notifications push de la version web, reçues page fermée ou en arrière-plan (Firebase
// Cloud Messaging). Identifiants publics de l'app web : ils ne donnent aucun droit d'envoi.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCxgepwhFDlVk6JKjie0nchbvy8s4bgKEI',
  authDomain: 'suivi-agent.firebaseapp.com',
  projectId: 'suivi-agent',
  storageBucket: 'suivi-agent.firebasestorage.app',
  messagingSenderId: '414870340041',
  appId: '1:414870340041:web:49d06407567463a56aa818',
});

// Les notifications envoyées par le serveur sont affichées par le navigateur (titre, texte,
// icône, lien vers l'app) : rien à faire ici.
firebase.messaging();
