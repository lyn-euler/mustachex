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
    test('in a nutshell example', () async {
      var template = '{{greeting_pascalCase}} {{what_pc}}!';
      var vars = {'greeting': 'HELLO'};
      String fulfillmentFunction(MissingVariableException variable) {
        if (variable.varName == 'what') {
          return 'WORLD';
        } else {
          return 'UNIVERSE';
        }
      }

      var processor = MustachexProcessor(
          initialVariables: vars, missingVarFulfiller: fulfillmentFunction);
      expect(await processor.process(template), equals('Hello World!'));
    });
  });
}
