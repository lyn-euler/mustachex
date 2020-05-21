/// MUSTACHE EXtended library
library mustachex;

import 'src/mustachex_processor.dart';
export 'src/mustachex_processor.dart'
    show MissingVariableException, MissingPartialException;

typedef FulfillmentFunction = String Function(
    MissingVariableException variable);

typedef PartialResolverFunction = String Function(
    MissingPartialException missingPartial);

String processMustachex(String source, Map variables,
    {FulfillmentFunction missingVarFulfiller,
    PartialResolverFunction partialsResolver}) {
  //TODO: meter la logica
}
