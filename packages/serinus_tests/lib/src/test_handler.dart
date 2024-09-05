import 'package:serinus/serinus.dart';
import 'package:serinus_tests/src/test_request.dart';

class TestHandler extends Handler {

  TestHandler(super.router, super.modulesContainer, super.config);

  @override
  Future<void> handleRequest(InternalRequest request, InternalResponse response) {
    throw UnimplementedError();
  }
  
  Future<TestResponse> handleTest(TestRequest request) async {
    final routeLookup = router.getRouteByPathAndMethod(
        request.path.endsWith('/')
            ? request.path.substring(0, request.path.length - 1)
            : request.path,
        request.method.toHttpMethod());
    final routeData = routeLookup.route;
    if (routeLookup.params.isNotEmpty) {
      request.params = routeLookup.params;
    }
    if (routeData == null) {
      throw NotFoundException(
          message:
              'No route found for path ${request.path} and method ${request.method}');
    }
    final injectables =
        modulesContainer.getModuleInjectablesByToken(routeData.moduleToken);
    final controller = routeData.controller;
    final routeSpec = controller.get(routeData);
    if (routeSpec == null) {
      throw InternalServerErrorException(
          message: 'Route spec not found for route ${routeData.path}');
    }
    final route = routeSpec.route;
    final handler = routeSpec.handler;
    final schema = routeSpec.schema;
    final scopedProviders = (injectables.providers
        .addAllIfAbsent(modulesContainer.globalProviders));
    RequestContext context =
        buildRequestContext(scopedProviders, request);
    Map<String, Metadata> metadata = {};
    if (controller.metadata.isNotEmpty) {
      for (final meta in controller.metadata) {
        if (meta is ContextualizedMetadata) {
          metadata[meta.name] = await meta.resolve(context);
        } else {
          metadata[meta.name] = meta;
        }
      }
    }
    if (route.metadata.isNotEmpty) {
      for (final meta in route.metadata) {
        if (meta is ContextualizedMetadata) {
          metadata[meta.name] = await meta.resolve(context);
        } else {
          metadata[meta.name] = meta;
        }
      }
    }
    context.metadata = metadata;
    await route.transform(context);
    if (schema != null) {
      final Map<String, dynamic> toParse = {};
      if (schema.body != null) {
        toParse['body'] = context.request.body?.value;
      }
      if (schema.query != null) {
        toParse['query'] = context.request.query;
      }
      if (schema.params != null) {
        toParse['params'] = context.request.params;
      }
      if (schema.headers != null) {
        toParse['headers'] = context.request.headers;
      }
      if (schema.session != null) {
        toParse['session'] = context.request.session.all;
      }
      final result = await schema.tryParse(value: toParse);
      context.request.headers.addAll(result['headers'] ?? <String, String>{});
      context.request.params.addAll(result['params'] ?? {});
      context.request.query.addAll(result['query'] ?? {});
    }
    for (final hook in config.hooks) {
      await hook.beforeHandle(context);
    }
    await route.beforeHandle(context);
    final response = await handler(context);
    await route.afterHandle(context, response);
    for (final hook in config.hooks) {
      await hook.afterHandle(context, response);
    }
    return TestResponse(response, context.res);
  }

}