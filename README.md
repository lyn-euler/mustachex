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
  var template = '{{greeting_pascalCase}} {{what_pc}}!';
  var vars = {'greeting':'HELLO'};
  String fulfillmentFunction(MissingVariableException variable) {
    if (variable.varName == 'what') {
      return 'WORLD';
    } else {
      return 'UNIVERSE';
    }
  }
  var rendered = processMustachex(template, vars, missingVarFulfiller: fulfillmentFunction);
  assert(rendered == 'Hello World!');
}
```
