import 'package:mustachex/mustachex.dart';
import 'package:mustachex/src/variables_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('Mustache extended', () {
    var classesJSON = {
      'classes': [
        {
          'name': 'claseUno',
          'fields': [
            {'name': 'field1', 'type': 'String'},
            {'name': 'Field2', 'type': 'int'},
          ]
        },
        {
          'name': 'claseDos',
          'fields': [
            {'name': 'field1', 'type': 'int'},
          ],
          'methods': [
            {
              'name': 'METHOD_UNO',
              'returntype': 'String',
              'parameters': [
                {'name': 'param1', 'type': 'String'},
                {'name': 'param2', 'type': 'double'}
              ]
            }
          ]
        }
      ]
    };
    var vars = VariablesResolver(classesJSON);

    setUp(() {
      awesome = Awesome();
    });

    test('First Test', () {
      expect(awesome.isAwesome, isTrue);
    });
  });
}
