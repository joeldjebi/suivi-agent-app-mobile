# Mobile – Suivi Agent

Application Flutter (Android et iOS) des **agents** et des **chefs d'équipe**. Connexion par **numéro de téléphone et mot de passe** fournis par la structure ; il n'y a pas de création de compte dans l'app.

## Écrans par rôle

| Agent | Chef d'équipe |
| --- | --- |
| **Journée** : choix de la zone, démarrer, pause, reprendre, terminer ; temps travaillé ; état du partage de position | **Équipe** : agents en journée (alertes d'abord : signal perdu, hors zone, position simulée), agents pas encore partis ; appeler un agent, le changer de zone |
| | **Carte** : agents en direct sur leurs zones (couleur selon le statut, alertes en rouge), liste à glisser, fiche de l'agent, itinéraire du jour avec distance parcourue ; fonds OpenStreetMap en 4 styles (Standard, Sobre, Sombre, Humanitaire) et options (zones, noms des agents, alertes seulement), mémorisés sur le téléphone ; adresse des tuiles modifiable avec `--dart-define=TILE_URL=...` |
| **Missions** : onglets Aperçu (progression de l'équipe, **sa propre contribution** — jamais celle des collègues) et Mes formulaires (en attente d'envoi, envoyés par jour) ; formulaires générés à partir des champs de la structure | **Demandes** : choix de zone à valider ou refuser (avec motif), délai restant |
| **Profil** : photo (appareil photo ou galerie), prénom, nom, email, numéro de connexion affiché (modifiable seulement par la structure), mot de passe (les autres appareils sont déconnectés, pas celui-ci), apparence (automatique, claire, sombre), notifications, transparence sur le suivi, déconnexion | **Missions** : onglets Aperçu (progression, détails, consignes), Équipe (contributions ; toucher un agent ouvre ses formulaires) et Formulaires (filtres agent, période, statut ; jours en accordéon, aujourd'hui ouvert ; fiche complète d'un formulaire, rejet avec motif) |
| | **Profil** : comme l'agent (photo, informations, mot de passe, apparence ; numéro non modifiable) |

## Personnalisation par la structure

Nom, couleur, logo, message d'accueil et téléphone du responsable se règlent sur le web (**Administration → Application mobile**).
L'écran de connexion garde l'apparence neutre « Suivi Agent ». La personnalisation s'applique **une fois l'utilisateur connecté** et disparaît à la déconnexion. Elle est mise en cache pour fonctionner hors connexion.

## Suivi de position et hors ligne

- Le suivi n'est actif que pendant la journée, et pendant la pause seulement si la structure l'a choisi. Il s'arrête à la fin de la journée.
- La fréquence suit le déplacement (filtre de 25 m). Un relevé de contrôle est fait toutes les 3 minutes si l'agent ne bouge pas.
- **Android** : un service de premier plan, avec une notification permanente « Journée en cours ». **iOS** : localisation en arrière-plan, avec l'indicateur bleu.
- Les positions et les formulaires sont enregistrés sur le téléphone (Drift), puis envoyés par lots dès que le réseau revient. Un renvoi ne crée pas de doublon.
- La tenue du suivi sur des téléphones d'entrée de gamme reste à valider par la preuve de concept prévue au cahier des charges (section 9).

## Lancer

```bash
flutter pub get
flutter run
```

Par défaut, l'API est `http://localhost:3000/api` (iOS) ou `http://10.0.2.2:3000/api` (émulateur Android). Sur un téléphone réel, indiquez l'adresse de la machine :

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:3000/api
```

Comptes de démo (mot de passe `Password123!`) : agents `07 02 02 02 01` à `07 02 02 02 06`, chefs d'équipe `07 01 01 01 01` et `07 01 01 01 02`.

## Design

Le design s'inspire des apps Apple : sobre et premium, sans dégradé ni ombre.
- **Grands titres** : la date en petites capitales, puis le titre de l'écran. À droite, les notifications et le logo de la structure.
- **Listes groupées** (comme dans Réglages) : cartes blanches sur fond gris, pictogrammes pleins, valeur à droite, chevron, note grise sous le groupe.
- **Anneaux de progression** (comme dans Activité) : temps travaillé dans « Ma journée », avancement des missions.
- **Contrôles iOS** : sélecteur segmenté, barre d'onglets avec libellés, boutons de 50 px dont un bouton secondaire gris.
- **Couleur** : celle de la structure, réservée aux actions et aux états.
- **Thèmes** : clair et sombre (noir pur), en suivant le réglage du téléphone.

Le code se trouve dans `lib/design/` (`tokens.dart`, `components.dart`).

Pour régénérer les captures d'écran (rendu réel, police comprise, sans simulateur), dans `test/screens/goldens/` :

```bash
flutter test --tags screens --run-skipped --update-goldens test/screens
```

## Tests

```bash
flutter test
```

Test d'intégration complet, sur simulateur ou appareil, contre l'API locale (données de démo fraîches) :

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d "iPhone 17 Pro"
```

Après une modification du schéma local : `dart run build_runner build --force-jit`.
