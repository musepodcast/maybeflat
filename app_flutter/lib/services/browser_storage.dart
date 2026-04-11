import 'browser_storage_base.dart';
import 'browser_storage_stub.dart'
    if (dart.library.html) 'browser_storage_web.dart';

export 'browser_storage_base.dart';

BrowserStorage createBrowserStorage() => createPlatformBrowserStorage();
