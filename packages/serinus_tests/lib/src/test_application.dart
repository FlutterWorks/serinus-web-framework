import 'package:serinus/serinus.dart';
import 'package:serinus_tests/src/test_request.dart';

import 'test_handler.dart';

class TestApplication extends SerinusApplication {

  TestApplication({required super.entrypoint, required super.config});

  @override
  Future<void> serve() async {
    await initialize();
    return;
  }

  Controller getController<T extends Controller>() {
    final controllers = [];
    for(final module in modulesContainer.modules) {
      controllers.addAll(module.controllers);
    }
    return controllers.firstWhere((element) => element is T);
  }

  Module getModule<T extends Module>() {
    return modulesContainer.modules.firstWhere((element) => element is T);
  }

  Provider? getProvider<T extends Provider>() {
    return modulesContainer.get<T>();
  }

  Future<TestResponse> handle(TestRequest request) async {
    final handler = TestHandler(router, modulesContainer, config);
    try {
      return await handler.handleTest(request);
    } on SerinusException catch (e) {
      return TestResponse(e.message, ResponseProperties()..statusCode = e.statusCode);
    }
  }

  bool canHandle(TestRequest request) {
    final routeExists = router.getRouteByPathAndMethod(request.path, request.method.toHttpMethod());
    return routeExists.route != null;
  }

}