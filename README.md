# MUSTACHE EXtended for Dart

The features of mustache with the addition of:

- recasing variables

## Usage

A simple usage example:

```dart
import 'package:mustachex/mustachex.dart';

main() {
  var template = '{{greeting_pascalCase}} {{what_pc}}!';
  var vars = {'greeting':'HELLO', 'what':'WORLD'});
  var rendered = processMustachex(template,vars);
  assert(rendered == 'Hello World!');
}
```
