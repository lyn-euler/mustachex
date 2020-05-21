/// MUSTACHE EXtended library
library mustachex;

import 'src/mustachex_processor.dart';

typedef FulfillmentFunction = String Function(String varName);

String processMustachex(String source, Map variables,
    {FulfillmentFunction missingVarFulfiller}) {
  //TODO: meter la logica
}
