import 'package:sembast_web/sembast_web.dart';

Future<Database> openLocalDatabase(String name) {
  return databaseFactoryWeb.openDatabase(name);
}
