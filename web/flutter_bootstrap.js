{{flutter_js}}
{{flutter_build_config}}

// Démarrage immédiat : le chargeur n'attend plus l'installation du service worker (jusqu'à
// 4 s au premier passage, pendant qu'il téléchargeait aussi la version de l'app inutile au
// navigateur). Le service worker est installé ensuite, en arrière-plan (index.html).
window.pxServiceWorkerVersion = {{flutter_service_worker_version}};
_flutter.loader.load();
