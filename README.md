# MUSTACHE EXtended for Dart

The features of mustache with the addition of:

- recasing variables
- missing variables fulfillment

## Usage

A simple usage example:

```dart
import 'package:mustachex/mustachex.dart';

main() {
  var template = '{{greeting_pascalCase}} {{what_pc}}!';
  var vars = {'greeting':'HELLO'};
  fulfillmentFunction(String varName){
    if(varName == 'what') return 'WORLD';
  }
  var rendered = processMustachex(template,vars, missingVarFulfiller: fulfillmentFunction);
  assert(rendered == 'Hello World!');
}
```
