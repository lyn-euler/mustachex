# MUSTACHE EXtended for Dart

The features of mustache with the addition of:

- recasing variables
- missing variables fulfillment
- hasVarName check

## Usage

A simple usage example:

```dart
import 'package:mustachex/mustachex.dart';

main() {
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
  var rendered = await processor.process(template);
  assert(rendered == 'Hello World!');
}
```
