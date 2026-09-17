// Drift's database worker for the web build. Compiled by tool/build_web.sh:
//   dart compile js -O4 -o web/drift_worker.js web/drift_worker.dart   (run in app/)
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
