/// App mobile : un téléphone.
bool browserIsMobile() => true;

void browserKeepAwake(bool on) {}

Future<bool> browserNotificationsAllowed() async => false;

bool browserNotify(String tag, String title, String body) => false;
