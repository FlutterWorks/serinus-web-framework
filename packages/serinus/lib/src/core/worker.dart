import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../adapters/adapters.dart';
import '../containers/module_container.dart';
import '../containers/router.dart';
import '../enums/enums.dart';
import '../services/logger_service.dart';
import 'core.dart';

/// The [Worker] class is used to create a worker.
class Worker {
  /// The [commands] property is a SendPort that is used to send commands to the worker.
  final SendPort commands;

  /// The [responses] property is a ReceivePort that is used to receive responses from the worker.
  final ReceivePort responses;
  final Map<int, Completer<Object?>> _activeRequests = {};
  bool _closed = false;

  /// The [spawn] method is a static method used to create a worker.
  static Future<Worker> spawn(
      int id,
      Module entrypoint,
      ModulesContainer modulesContainer,
      Router router,
      ApplicationConfig config,
      LogLevel level,
      LoggerService loggerService,
      Function(dynamic message) onMessage) async {
    // Create a receive port and add its initial message handler
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ));
    };

    // Spawn the isolate.
    try {
      await Isolate.spawn(
          _startRemoteIsolate,
          WorkerSpawnMessage(
            sendPort: initPort.sendPort,
            entrypoint: entrypoint,
            modulesContainer: modulesContainer,
            router: router,
            host: config.host,
            port: config.port,
            level: level,
            loggerService: loggerService,
            poweredByHeader: config.poweredByHeader,
            securityContext: config.securityContext,
          ));
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort receivePort, SendPort sendPort) =
        await connection.future;

    return Worker._(receivePort, sendPort, onMessage);
  }

  Worker._(this.responses, this.commands, Function(dynamic message) onMessage) {
    responses.listen((message) {
      onMessage(message);
      if (message is (int, Object?)) {
        _handleResponsesFromIsolate(message);
      }
    });
  }

  void _handleResponsesFromIsolate(dynamic message) {
    final (int id, Object? response) = message as (int, Object?);
    final completer = _activeRequests.remove(id)!;

    if (response is RemoteError) {
      completer.completeError(response);
    } else {
      completer.complete(response);
    }

    if (_closed && _activeRequests.isEmpty) {
      responses.close();
    }
  }

  static void _handleCommandsToIsolate(
    ReceivePort receivePort,
    SendPort sendPort,
    SerinusApplication app,
  ) {
    receivePort.listen((message) {
      if (message is Hook) {
        app.use(message);
      }
      if (message is Tracer) {
        app.trace(message);
      }
      if (message == 'close') {
        app.close();
        sendPort.send(WorkerMessage.closed);
        receivePort.close();
      }
      if (message == 'shutdown') {
        app.shutdown();
        sendPort.send(WorkerMessage.shutdown);
        receivePort.close();
      }
      if (message == 'listen') {
        app.serve();
        sendPort.send(WorkerMessage.listening);
      }
    });
  }

  static void _startRemoteIsolate(WorkerSpawnMessage message) async {
    final receivePort = ReceivePort();
    message.sendPort.send(receivePort.sendPort);
    final isolateServer = SerinusHttpAdapter(
      host: message.host,
      port: message.port,
      poweredByHeader: message.poweredByHeader,
      securityContext: message.securityContext,
    );
    await isolateServer.init();
    final app = SerinusApplication(
        entrypoint: message.entrypoint,
        modulesContainer: message.modulesContainer,
        router: message.router,
        isChild: true,
        config: ApplicationConfig(
          host: message.host,
          port: message.port,
          poweredByHeader: message.poweredByHeader,
          securityContext: message.securityContext,
          serverAdapter: isolateServer,
        ),
        level: message.level,
        loggerService: message.loggerService);
    _handleCommandsToIsolate(receivePort, message.sendPort, app);
  }

  /// The [close] method is used to close the worker.
  /// It also send a close message to the worker to shutdown the isolate.
  void close() {
    if (!_closed) {
      _closed = true;
      commands.send('close');
      if (_activeRequests.isEmpty) {
        responses.close();
      }
    }
  }
}

/// The [WorkerSpawnMessage] class is used to define the message that is sent to the worker.
class WorkerSpawnMessage {
  /// The [sendPort] property is used to define the send port.
  final SendPort sendPort;

  /// The [entrypoint] property is used to define the entrypoint.
  final Module entrypoint;

  /// The [modulesContainer] property is used to define the modules container.
  final ModulesContainer modulesContainer;

  /// The [router] property is used to define the router.
  final Router router;

  /// The [host] property is used to define the host.
  final String host;

  /// The [port] property is used to define the port.
  final int port;

  /// The [level] property is used to define the log level.
  final LogLevel level;

  /// The [loggerService] property is used to define the logger service.
  final LoggerService loggerService;

  /// The [poweredByHeader] property is used to define the powered by header.
  final String poweredByHeader;

  /// The [securityContext] property is used to define the security context.
  final SecurityContext? securityContext;

  /// The [WorkerSpawnMessage] constructor is used to create a new instance of the [WorkerSpawnMessage] class.
  WorkerSpawnMessage({
    required this.sendPort,
    required this.entrypoint,
    required this.modulesContainer,
    required this.router,
    required this.host,
    required this.port,
    required this.level,
    required this.loggerService,
    required this.poweredByHeader,
    required this.securityContext,
  });
}

/// The [WorkerMessage] enum is used to define the messages that can be sent to the worker.
enum WorkerMessage {
  /// The [listening] message is sent when the worker is listening.
  listening,

  /// The [closed] message is sent when the worker is closed.
  closed,

  /// The [shutdown] message is sent when the worker is shutdown.
  shutdown,
}
