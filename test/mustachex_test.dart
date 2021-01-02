import 'package:mustache_template/mustache.dart';
import 'package:mustachex/mustachex.dart';
import 'package:mustachex/src/variables_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('Mustache extended', () {
    test('in a nutshell example', () async {
      var template = "{{#hasFoo}} this won't be rendered{{/hasFoo}}"
          '{{greeting_pascalCase}} {{world_pc}}!'
          '{{#hasBar}} This neither {{/hasBar}}';
      var vars = {'greeting': 'HELLO', 'foo': false};
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
    test('hasFoo guard behaviour', () async {
      var template = "{{#hasFoo}} this won't be rendered {{/hasFoo}}"
          '{{#hasBar}} this neither {{/hasBar}}'
          '{{^hasBaz}} nor this {{/hasBaz}}';
      var vars = {'foo': false, 'baz': true};

      var processor = MustachexProcessor(initialVariables: vars);
      expect(await processor.process(template), isEmpty);
    });
    test('funcion de partials', () async {
      var partials = <String, String>{
        'foo': '''Foo: hola {{foo}}''',
        'bar': '''hello {{foo}}'''
      };
      String partialsFunc(MissingPartialException e) => partials[e.partialName];

      var workingProcessor = MustachexProcessor(
          partialsResolver: partialsFunc, initialVariables: {'foo': 'f00'});
      var processorWithoutPartialsResolver =
          MustachexProcessor(initialVariables: {'foo': 'f00'});
      var template = '{{>foo}}\n{{> bar}}';
      var processed = await workingProcessor.process(template);
      expect(processorWithoutPartialsResolver.process(template),
          throwsA(isA<MissingPartialsResolverFunction>()));
      expect(processed, contains('hola f00'));
      expect(processed, contains('hello f00'));
      expect(workingProcessor.process('{{>nonExistentPartial}}'),
          throwsA(isA<MissingPartialException>()));
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
    test('renderiza clases', () async {
      var classesJSON = {
        'classes': [
          {
            'name': 'claseUno',
            'fields': [
              {'name': 'field1', 'type': 'String', 'final': true},
              {'name': 'Field2', 'type': 'int', 'docs': 'tieneDocs'},
            ],
            'methods': []
          },
          {
            'name': 'clase_dos',
            'fields': [
              {'name': 'field1', 'type': 'int'},
            ],
            'methods': [
              {
                'name': 'METHOD_UNO',
                'returnType': 'String',
                'parameters': [
                  {'name': 'param1', 'type': 'String'},
                  {'name': 'param2', 'type': 'double'}
                ]
              },
              {'name': 'method-dos', 'returnType': 'String'}
            ]
          }
        ]
      };
      var vars = VariablesResolver(classesJSON);
      var processor = MustachexProcessor(variablesResolver: vars);
      var template = '''
      {{#classes}}
      class {{name_pc}} {
        {{#fields}}
        {{#hasDocs}}///{{docs}}{{/hasDocs}}
        {{#hasFinal}}final {{/hasFinal}}{{type}} {{name_cc}};
        {{/fields}}

        {{name_pc}}();

        {{#methods}}
        {{returnType_pc}} {{name_cc}}({{#hasParameters}}{{#parameters}}{{type}} {{name}},{{/parameters}}{{/hasParameters}}){}
        {{/methods}}
      }
      {{/classes}}
      ''';
      var procesado = await processor.process(template);
      expect(procesado, contains('class ClaseUno'));
      expect(procesado, contains('///tieneDocs'));
      expect(procesado, contains('final String field1;'));
      expect(procesado, contains('int field2;'));
      expect(procesado, contains('String methodDos()'));
      expect(procesado, contains('String param1,double param2'));
      //puts nothing as methods
      expect(
          procesado, contains(RegExp(r'ClaseUno\(\);\s*}\s*class ClaseDos')));
    });
    test("Missing variable has good exception", () async {
      var vars = {
        'parent1': [
          {
            'parent2': [
              {'var': 'sorpi'}
            ]
          },
          {'parent2': []},
        ]
      };
      var p = MustachexProcessor(variablesResolver: VariablesResolver(vars));
      var src = '{{#parent1}}{{#parent2}}'
          '{{var_paramCase}}'
          '{{/parent2}}{{/parent1}}';
      // var t = Template(src);
      // t.renderString(vars);
      expect(() => p.process(src), throwsA(MissingVariableException));
      MissingVariableException exception;
      try {
        await p.process(src);
      } catch (e) {
        exception = e;
      }
      expect(exception, isNotNull);
      expect(exception.humanReadableVariable,
          equals("['parent1'],['parent2'],['var']"));
      expect(exception.parentCollectionsWithRequest,
          equals(['parent1', 'parent2', 'var_paramCase']));
      expect(exception.parentCollectionsWithVarName,
          equals(['parent1', 'parent2', 'var']));
      expect(exception.recasing, equals('paramCase'));
      expect(exception.request, equals('var_paramCase'));
      expect(exception.varName, equals('var'));
      expect(exception.parentCollections, equals(['parent1', 'parent2']));
    });
  });
}
