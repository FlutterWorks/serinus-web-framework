import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';

import '../adapters/adapters.dart';
import '../containers/module_container.dart';
import '../containers/router.dart';
import '../engines/view_engine.dart';
import '../enums/enums.dart';
import '../errors/initialization_error.dart';
import '../extensions/iterable_extansions.dart';
import '../global_prefix.dart';
import '../handlers/request_handler.dart';
import '../handlers/websocket_handler.dart';
import '../http/http.dart';
import '../injector/explorer.dart';
import '../mixins/mixins.dart';
import '../services/logger_service.dart';
import '../versioning.dart';
import 'core.dart';
import 'worker.dart';

/// The [Application] class is used to create an application.
sealed class Application {
  /// The [logger] property contains the logger of the application.
  final Logger logger = Logger('Application');

  /// The [level] property contains the log level of the application.
  final LogLevel level;

  /// The [entrypoint] property contains the entry point of the application.
  final Module entrypoint;
  bool _enableShutdownHooks = false;

  /// The [loggerService] property contains the logger service of the application.
  LoggerService? loggerService;

  /// The [modulesContainer] property contains the modules container of the application.
  ModulesContainer modulesContainer;

  /// The [router] property contains the router of the application.
  Router router;

  /// The [config] property contains the application configuration.
  final ApplicationConfig config;

  Application({
    required this.entrypoint,
    required this.config,
    this.level = LogLevel.debug,
    Router? router,
    ModulesContainer? modulesContainer,
    LoggerService? loggerService,
  })  : router = router ?? Router(),
        loggerService = loggerService ?? LoggerService(level: level),
        modulesContainer = modulesContainer ?? ModulesContainer();

  /// The [url] property contains the URL of the application.
  String get url;

  /// The [server] property contains the server of the application.
  HttpServer get server => config.serverAdapter.server;

  /// The [adapter] property contains the adapter of the application.
  HttpAdapter get adapter => config.serverAdapter as HttpAdapter;

  /// The [enableShutdownHooks] method is used to enable the shutdown hooks.
  void enableShutdownHooks() {
    if (!_enableShutdownHooks) {
      _enableShutdownHooks = true;
      ProcessSignal.sigint.watch().listen((event) async {
        await close();
        exit(0);
      });
    }
  }

  /// The [initialize] method is used to initialize the application.
  @internal
  Future<void> initialize();

  /// The [shutdown] method is used to shutdown the application.
  @internal
  Future<void> shutdown();

  /// The [register] method is used to register the application.
  Future<void> register();

  /// The [serve] method is used to serve the application.
  Future<void> serve();

  /// The [close] method is used to close the application.
  Future<void> close();
}

/// The [SerinusApplication] class is used to create a new instance of the [Application] class.
class SerinusApplication extends Application {
  /// The [isChild] property returns true if the application is contained in a Worker of a [OrchestratorApplication].
  final bool isChild;

  /// The [SerinusApplication] constructor is used to create a new instance of the [SerinusApplication] class.
  SerinusApplication({
    required super.entrypoint,
    required super.config,
    super.level,
    super.loggerService,
    super.modulesContainer,
    super.router,
    this.isChild = false,
  });

  @override
  String get url => config.baseUrl;

  /// The [useViewEngine] method is used to set the view engine of the application.
  void useViewEngine(ViewEngine viewEngine) {
    config.viewEngine = viewEngine;
  }

  /// The [enableVersioning] method is used to enable versioning.
  void enableVersioning(
      {required VersioningType type, int version = 1, String? header}) {
    config.versioningOptions =
        VersioningOptions(type: type, version: version, header: header);
  }

  /// The [setGlobalPrefix] method is used to set the global prefix of the application.
  void setGlobalPrefix(GlobalPrefix prefix) {
    config.globalPrefix = prefix;
  }

  @override
  Future<void> serve() async {
    await initialize();
    logger.info('Starting server on $url');
    final requestHandler = RequestHandler(router, modulesContainer, config);
    final wsHandler = WebSocketHandler(router, modulesContainer, config);
    Future<void> Function(InternalRequest, InternalResponse) handler;
    try {
      for (final adapter in config.adapters.values) {
        if (adapter.shouldBeInitilized) {
          await adapter.init(modulesContainer, config);
        }
      }
      adapter.listen(
        (request, response) {
          handler = requestHandler.handle;
          if (config.adapters[WsAdapter] != null &&
              config.adapters[WsAdapter]?.canHandle(request) == true) {
            handler = wsHandler.handle;
          }
          return handler(request, response);
        },
        errorHandler: (e, stackTrace) => logger.severe(e, stackTrace),
      );
    } on SocketException catch (e) {
      logger.severe('Failed to start server on ${e.address}:${e.port}');
      await close();
    }
  }

  @override
  Future<void> close() async {
    for (final adapter in config.adapters.values) {
      await adapter.close();
    }
    await config.serverAdapter.close();
    await shutdown();
  }

  @override
  Future<void> initialize() async {
    if (isChild) {
      return;
    }
    if (entrypoint is DeferredModule) {
      throw InitializationError(
          'The entry point of the application cannot be a DeferredModule');
    }
    if (!modulesContainer.isInitialized) {
      await modulesContainer.registerModules(
          entrypoint, entrypoint.runtimeType, config);
    }
    final explorer = Explorer(modulesContainer, router, config);
    explorer.resolveRoutes();
    await modulesContainer.finalize(entrypoint, config);
  }

  @override
  Future<void> shutdown() async {
    if (isChild) {
      return;
    }
    logger.info('Shutting down server');
    final registeredProviders =
        modulesContainer.modules.map((e) => e.providers).flatten();
    for (final provider in registeredProviders) {
      if (provider is OnApplicationShutdown) {
        await provider.onApplicationShutdown();
      }
    }
  }

  @override
  Future<void> register() async {
    if (isChild) {
      return;
    }
    await modulesContainer.registerModules(
        entrypoint, entrypoint.runtimeType, config);
  }

  /// The [use] method is used to add a hook to the application.
  void use(Hook hook) {
    config.addHook(hook);
    logger.info('Hook ${hook.runtimeType} added to application');
  }

  /// The [trace] method is used to add a tracer to the application.
  void trace(Tracer tracer) {
    config.registerTracer(tracer);
    logger.info(
        'Tracer ${tracer.name}(${tracer.runtimeType}) added to application');
  }
}

/// The [OrchestratorApplication] class is used to create a new instance of the [Application] class.
///
/// The [OrchestratorApplication] class is used to create an application that can spawn multiple workers.
///
/// A [Worker] is a [Isolate] that runs a [SerinusApplication].
class OrchestratorApplication extends Application {
  /// The [instances] property contains the number of instances of the application.
  final int instances;

  /// The [workers] property contains the workers of the application.
  final Map<int, Worker> workers = {};

  /// The [OrchestratorApplication] constructor is used to create a new instance of the [OrchestratorApplication] class.
  OrchestratorApplication({
    required super.entrypoint,
    required super.config,
    super.level,
    super.router,
    super.modulesContainer,
    super.loggerService,
    this.instances = 1,
  });

  @override
  String get url => config.baseUrl;

  @override
  Future<void> initialize() async {
    if (entrypoint is DeferredModule) {
      throw InitializationError(
          'The entry point of the application cannot be a DeferredModule');
    }
    if (!modulesContainer.isInitialized) {
      await modulesContainer.registerModules(
          entrypoint, entrypoint.runtimeType, config);
    }
    final explorer = Explorer(modulesContainer, router, config);
    explorer.resolveRoutes();
    await modulesContainer.finalize(entrypoint, config);
    for (int i = 0; i < instances; i++) {
      workers[i] = await Worker.spawn(i, entrypoint, modulesContainer, router,
          config, level, loggerService!, (dynamic message) {
        if (message == WorkerMessage.closed) {
          workers.remove(i);
          logger.info('Worker #$i closed');
        }
        if (message == WorkerMessage.shutdown) {
          workers.remove(i);
          logger.info('Worker #$i shutdown');
        }
        if (message == WorkerMessage.listening) {
          logger.info('Worker #$i listening');
        }
      });
    }
  }

  @override
  Future<void> shutdown() async {
    final registeredProviders =
        modulesContainer.modules.map((e) => e.providers).flatten();
    for (final provider in registeredProviders) {
      if (provider is OnApplicationShutdown) {
        await provider.onApplicationShutdown();
      }
    }
  }

  @override
  Future<void> register() async {
    await modulesContainer.registerModules(
        entrypoint, entrypoint.runtimeType, config);
  }

  @override
  Future<void> serve() async {
    await initialize();
    final requestHandler = RequestHandler(router, modulesContainer, config);
    final wsHandler = WebSocketHandler(router, modulesContainer, config);
    Future<void> Function(InternalRequest, InternalResponse) handler;
    try {
      for (final application in workers.entries) {
        application.value.commands.send('listen');
      }
      for (final adapter in config.adapters.values) {
        if (adapter.shouldBeInitilized) {
          await adapter.init(modulesContainer, config);
        }
      }
      adapter.listen(
        (request, response) {
          handler = requestHandler.handle;
          if (config.adapters[WsAdapter] != null &&
              config.adapters[WsAdapter]?.canHandle(request) == true) {
            handler = wsHandler.handle;
          }
          return handler(request, response);
        },
        errorHandler: (e, stackTrace) => logger.error(e, stackTrace),
      );
    } on SocketException catch (e) {
      logger.severe('Failed to start server on ${e.address}:${e.port}');
      await close();
    }
  }

  @override
  Future<void> close() async {
    for (final adapter in config.adapters.values) {
      await adapter.close();
    }
    await config.serverAdapter.close();
    for (final worker in workers.entries) {
      worker.value.commands.send('close');
      logger.info('Closing worker #${worker.key}');
    }
    await shutdown();
  }
}
