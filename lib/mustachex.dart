/// MUSTACHE EXtended library
library mustachex;

import 'package:mustachex/src/variables_resolver.dart';

import 'src/mustachex_processor.dart';
export 'src/mustachex_processor.dart'
    show MissingVariableException, MissingPartialException;

typedef FulfillmentFunction = String Function(
    MissingVariableException variable);

typedef PartialResolverFunction = String Function(
    MissingPartialException missingPartial);

String processMustachex(String source, Map variables,
    {FulfillmentFunction missingVarFulfiller,
    PartialResolverFunction partialsResolver,
    VariablesResolver variablesResolver}) {
  //TODO: meter la logica
}
