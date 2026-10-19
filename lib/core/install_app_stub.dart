/// Application installée (téléphone) : rien à proposer.
bool installStandalone() => true;

bool installCanPrompt() => false;

Future<bool> installPrompt() async => false;

bool installIsIOS() => false;
