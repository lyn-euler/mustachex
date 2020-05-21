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
          'name': 'clase_dos',
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
    test('in a nutshell example', () {
      var template = '{{greeting_pascalCase}} {{what_pc}}!';
      var vars = {'greeting': 'HELLO'};
      fulfillmentFunction(MissingVariableException variable) {
        if (varName == 'what') return 'WORLD';
      }

      var rendered = processMustachex(template, vars,
          missingVarFulfiller: fulfillmentFunction);
      expect(rendered, equals('Hello World!'));
    });
  });
}
