import 'package:serinus_tests/src/test_request.dart';

void expectStatus(TestResponse response, int statusCode){
  return expect(response.properties.statusCode, statusCode);
}