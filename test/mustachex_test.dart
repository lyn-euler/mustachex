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
      var template = '{{greeting_pascalCase}} {{world_pc}}!';
      var vars = {'greeting': 'HELLO'};
      String fulfillmentFunction(MissingVariableException variable) {
        if (variable.varName == 'world') {
          return 'WORLD';
        } else {
          return 'UNIVERSE';
        }
      }

      var processor = MustachexProcessor(
          initialVariables: vars, missingVarFulfiller: fulfillmentFunction);
      expect(await processor.process(template), equals('Hello World!'));
      expect(await processor.process('{{greeting_pc}} {{xxx_pc}}!'),
          equals('Hello Universe!'));
    });
    test('guarda de has', () async {
      var vars = {
        'items': [
          {'name': 'uno'},
          {'name': 'dos'}
        ]
      };
      var processor = MustachexProcessor(initialVariables: vars);
      var template = '{{#hasItems}}{{#items}} -{{name}}{{/items}}{{/hasItems}}';
      var procesado = await processor.process(template);
      expect(procesado, contains('-uno'));
      expect(procesado, contains('-dos'));
      template = '{{#hasSorpos}}{{#items}} -{{name}}{{/items}}{{/hasSorpos}}';
      procesado = await processor.process(template);
      expect(procesado, isNot(contains('-uno')));
      expect(procesado, isNot(contains('-dos')));
    });
  });
}
