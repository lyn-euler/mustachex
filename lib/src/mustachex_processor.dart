import 'dart:async';

import 'package:mustache/mustache.dart';
import 'package:mustache_recase/mustache_recase.dart' as mustache_recase;
import 'package:mustachex/src/variable_recase_decomposer.dart';
import 'package:recase/recase.dart';

import '../mustachex.dart';

typedef FulfillmentFunction = FutureOr<String> Function(
    MissingVariableException variable);

typedef PartialResolverFunction = FutureOr<String> Function(
    MissingPartialException missingPartial);

typedef _PartialsResolver = Template Function(String partialName);

class MissingPartialsResolverFunction implements Exception {
  @override
  String toString() => 'No partial resolver function provided';
}

class MustachexProcessor {
  FulfillmentFunction missingVarFulfiller;
  PartialResolverFunction partialsResolver;
  VariablesResolver variablesResolver;

  /// Acá guardás una cache para eficientizar las ejecuciones del
  /// processMustacheThrowingIfAbsent que se ejecuta con lo mismo varias veces
  final Map<String, Map> _sourceCache = {};

  MustachexProcessor(
      {Map initialVariables,
      this.missingVarFulfiller,
      this.partialsResolver,
      this.variablesResolver}) {
    variablesResolver ??= VariablesResolver(initialVariables);
  }

  Future<String> process(String source) async {
    return await _processMustacheThrowingIfAbsent(
        source, variablesResolver.getAll,
        partialsResolver: _partialsResolverAdapted);
  }

  Template _partialsResolverAdapted(String name) {
    if (partialsResolver == null) {
      throw MissingPartialsResolverFunction();
    }
    return Template(partialsResolver(MissingPartialException(name)));
  }

  /// Processes a mustache formatted source with the given variables and throws
  /// [_MustacheMissingException] whenever any of them is missing
  Future<String> _processMustacheThrowingIfAbsent(
      String source, Map resolverVars,
      {_PartialsResolver partialsResolver}) async {
    if (_sourceCache[source] == null) {
      _sourceCache[source] = {
        'template': Template(source,
            partialResolver: partialsResolver, htmlEscapeValues: false),
        'variables': _mustacheVars(source)
      };
    }
    Template template = _sourceCache[source]['template'];
    Map variables = _sourceCache[source]['variables'];
    var vars = Map.from(resolverVars);
    vars.addAll(mustache_recase.cases);
    Future<String> _tryRender() async {
      try {
        return template.renderString(variablesResolver.getAll);
      } on TemplateException catch (e) {
        // print(
        //     "There is a missing value for '${ex.humanReadableVariable}' mustache "
        //     'section tag. Trying to solve this...');
        if (e.message.contains('section tag')) {
          //Primero nos fijamos si es una guarda tipo hasXxxYyyyyyZzzz
          var ex = MissingSectionTagException(e, variables);
          var variable = ex.request;
          if (variable.startsWith('has')) {
            var recasedName = ReCase(variable.substring(3)).camelCase;
            var iterations = _getMustacheIterations(ex, recasedName);
            if (iterations.isNotEmpty) {
              var mapToReplace =
                  iterations.first.variablesResolverPosition.first;
              var assign =
                  _recursivelyProcessed(iterations, variable, recasedName);
              variablesResolver[mapToReplace] = assign;
              // print('Problem solved by setting all intances of '
              //     "the last submap with a '$variable' field saying wether "
              //     "the field '$recasedName' is set or not.");
            } else {
              var request = ex.parentCollections;
              var storeLocation = List.from(request);
              request.add(recasedName);
              storeLocation.add(variable);
              var storedVar = variablesResolver.get(request);
              variablesResolver[storeLocation] = _processStoreValue(storedVar);
              // print('Problem solved by defining '
              //     "'$variable' to ${variablesResolver[storeLocation]}");
            }
            return _tryRender();
          } else {
            //No es del tipo hasXxxYyy. Le falta la lista directamente
            throw ex;
          }
        } else if (e.message.contains('variable tag')) {
          var ex = MissingVariableException(e, variables);
          // print(
          //     "There is a missing value for '${ex.humanReadableVariable}' mustache "
          //     'variable. Trying to solve this...');
          //Primero nos fijamos si falta el valor o sólo hay que recasearlo
          dynamic recasingAttempt =
              variablesResolver.get(ex.parentCollectionsWithVarName);
          if (recasingAttempt != null) {
            // guardamos el valor recaseado
            variablesResolver[ex.parentCollectionsWithRequest] =
                variablesResolver.get(ex.parentCollectionsWithRequest);
            // print("Problem solved by recasing it to '$recasingAttempt'");
          } else {
            if (missingVarFulfiller == null) throw ex;
            var value = await missingVarFulfiller(ex);
            variablesResolver[ex.parentCollectionsWithVarName] = value;
            // print("Problem solved by asking user ('$value' answered)");
          }
          return _tryRender();
        } else {
          throw UnsupportedError(
              "Don't know how to process this mustache exception: $e");
        }
      }
    }

    return _tryRender();
  }

  List<_MustacheIteration> _getMustacheIterations(
      MissingSectionTagException e, String recasedName) {
    var iterations = <_MustacheIteration>[];
    var request = <String>[];
    var elements = List.from(e.parentCollections);
    // elements.add(recasedName);
    var resolvedVar;
    for (String collection in elements) {
      request.add(collection);
      try {
        resolvedVar = variablesResolver[request];
      } on ArgumentError {
        try {
          resolvedVar = iterations.last.iteration
              .firstWhere((elem) => elem.containsKey(collection))[collection];
        } catch (e) {
          break;
        }
      }
      if (resolvedVar is List) {
        if (resolvedVar.isEmpty) {
          break;
        } else if (resolvedVar.every((e) => e is Map)) {
          iterations.add(
              _MustacheIteration(resolvedVar.cast<Map>(), List.from(request)));
        } else {
          _throwImpossibleState();
        }
      }
    }
    return iterations;
  }
}

class MissingPartialException implements Exception {
  final String partialName;
  MissingPartialException(this.partialName);

  @override
  String toString() => "Missing partial: Partial '$partialName' not found";
}

/// Indicates that the `request` value wasn't provided
/// Note that `request` is automatically decomposed from `varName`(_`recasing`)?
class MissingVariableException extends _MustacheMissingException {
  @override
  VariableRecaseDecomposer _d;
  @override
  List<String> _parentCollections;

  MissingVariableException(TemplateException e, Map sourceVariables)
      : super(
            e.message.substring(36, e.message.length - 1), e, sourceVariables);
}

/// Indicates that the `request` value wasn't providedvariables
/// Note that `request` is automatically decomposed from `varName`(_`recasing`)?
class MissingSectionTagException extends _MustacheMissingException {
  @override
  VariableRecaseDecomposer _d;
  @override
  List<String> _parentCollections;

  MissingSectionTagException(TemplateException e, Map sourceVariables)
      : super(
            e.message.substring(35, e.message.length - 1), e, sourceVariables);
}

/// The parent class that does the computations
class _MustacheMissingException {
  VariableRecaseDecomposer _d;
  List<String> _parentCollections;

  _MustacheMissingException(
      String missing, TemplateException e, Map sourceVariables) {
    _d = VariableRecaseDecomposer(missing);
    var sourceBefore = e.source.substring(0, e.offset);
    //cambiar las variables si estás en un {{#mapa|lista}}
    _parentCollections = _processParentMaps(sourceBefore) ?? [];
    if (_parentCollections.isNotEmpty) {
      _parentCollections.forEach((pc) {
        if (sourceVariables[pc] is Map) {
          sourceVariables = sourceVariables[pc];
        } else if (sourceVariables[pc] is List) {
          sourceVariables = sourceVariables[pc].toMap();
        }
      });
      Map val = sourceVariables[varName];
      if (val != null) {
        var ret =
            val.entries.firstWhere((e) => e.value == null, orElse: () => null);
        if (ret != null) {
          _parentCollections.add(ret.key.toString());
        }
      }
    }

    // this._parentCollections = _processParentMaps(_d.varName, sourceVariables) ?? [];
  }

  /// The complete requested variable string, like varName_constantCase
  String get request => _d.request;

  /// The variable part of the request, like varName
  String get varName => _d.varName;

  /// The eventual recasing part of the request, like camelCase
  String get recasing => _d.recasing;

  /// The maps that contains the missing value. For example, \[a,b\] means that
  /// the missing variable with `varName` 'missing' should be stored in
  /// variablesResolver\["a"\]\["b"\]\["missing"\]
  List<String> get parentCollections => _parentCollections;

  /// Same as `parentCollections` but with the varName added at the end
  List<String> get parentCollectionsWithVarName {
    var vals = List<String>.from(_parentCollections);
    vals.add(_d.varName);
    return vals;
  }

  /// for logging or informing the user wchich variable is missing beneath maps
  String get humanReadableVariable {
    var ret = parentCollectionsWithVarName.join("'],['");
    if (parentCollectionsWithVarName.length > 1) {
      ret = "['$ret']";
    }
    return ret;
  }

  /// Same as `parentCollections` but with the request added at the end
  List<String> get parentCollectionsWithRequest {
    var vals = List<String>.from(_parentCollections);
    vals.add(_d.request);
    return vals;
  }

  /// usado para scanear el código mustache por tokens que nombren a los maps
  final _beginToken = RegExp(r'{{ ?# ?(.*?)}}'),
      _endToken = RegExp(r'{{ ?\/ ?(.*?)}}');

  /// Scanea el código mustache y devuelve una lista con los maps que quedaron
  /// abiertos. Ej: {{#uno}} {{#dos}}{{/dos}} {{#tres}} devuelve [uno,tres]
  List<String> _processParentMaps(String source) {
    var open = _beginToken.allMatches(source).map((m) => m.group(1)),
        close = _endToken.allMatches(source).map((m) => m.group(1)).toList();
    var ret = open.where((e) => !close.remove(e)).toList();
    return ret;
  }
  // List<String> _processParentMaps(String varName, Map sourceVariables) {
  //   // Hace un BFS para encontrar las keys de los mapas padres del varName q busca
  //   List<String> ret = [];
  //   if (sourceVariables.entries.any((e) => e.key == varName)) {
  //     return ret;
  //   } else {
  //     var maps = sourceVariables.entries.where((e) => e.value is Map);
  //     for (var map in maps) {
  //       var res = _processParentMaps(varName, map.value);
  //       if (res != null) {
  //         ret.add(map.key);
  //         ret.addAll(res);
  //         return ret;
  //       }
  //     }
  //     return null;
  //   }
  // }
}

Map<String, dynamic> _mustacheVars(String source) {
  var template = Template(source);
  return _gatherTemplateRequiredVars(template);
}

Map<String, dynamic> _gatherTemplateRequiredVars(Template template,
    [Map<String, dynamic> variables]) {
  var vars = variables ?? <String, dynamic>{};
  var nameRegExp = RegExp(r': (.*).$');
  while (true) {
    var error = _failing_gathering(template, vars);
    // , printMessage: true, printReturn: true);
    if (error == null) {
      return vars;
    } else {
      var e = error.message;
      var name = nameRegExp.firstMatch(e).group(1);
      if (e.contains('for variable tag')) {
        vars[name] = '%ValueOf$name%';
      } else {
        //up to this version, if not a variable, only a Section is possible
        var inSectionSrc = RegExp('{{([#^])$name}}([\\s\\S]*?){{/$name}}');
        List<Match> matches = inSectionSrc.allMatches(error.source).toList();
        for (var i = 0; i < matches.length; i++) {
          var type = matches[i].group(1);
          var contents = matches[i].group(2);
          var sectionSourceTemplate = Template(contents);
          // if (e.contains("for inverse section")) {
          // } else if (e.contains("for section")) {
          if (type == '^') {
            //inverse section
            vars['^$name'] ??= {};
            vars['^$name']
                .addAll(_gatherTemplateRequiredVars(sectionSourceTemplate));
          } else {
            vars[name] ??= {};
            vars[name]
                .addAll(_gatherTemplateRequiredVars(sectionSourceTemplate));
          }
        }
      }
    }
  }
}

TemplateException _failing_gathering(Template template, Map vars,
    {bool printMessage = false, bool printReturn = false}) {
  try {
    var variables = Map.from(vars);
    variables.addAll(mustache_recase.cases);
    var ret = template.renderString(variables);
    if (printReturn) print(ret);
    return null;
  } on TemplateException catch (e) {
    if (printMessage) print(e.message);
    return e;
  }
}

void _throwImpossibleState() {
  //Sí o sí tienen que ser listas de Maps
  throw StateError('Impossible state: This is a bug, please report it.');
}

/// Determines wether the hasStoredValue is true or false
bool _processStoreValue(storedVar) {
  if (storedVar == null) {
    return false;
  } else if (storedVar is bool) {
    return storedVar;
  } else if (storedVar is String) {
    return storedVar.isNotEmpty;
  } else if (storedVar is Iterable) {
    return storedVar.isNotEmpty;
  } else if (storedVar != null) {
    return true;
  } else {
    throw UnsupportedError(
        "Don't known what to do with a '${storedVar.runtimeType}' type."
        ' Should hasXXX return true or false?');
  }
}

/// Devuelve un map sacado de la primera iteración con todos sus elementos
/// procesados para devolver sus últimas instancias con el `hasName` correctamente
/// seteado según el estado de su item `name`
List<Map> _recursivelyProcessed(
    List<_MustacheIteration> iterations, String hasName, String name,
    [Map submap]) {
  var mapIdentifier = iterations.first.variablesResolverPosition.last;
  if (iterations.length > 1) {
    var ret = List<Map>.from(
        submap == null ? iterations.first.iteration : submap[mapIdentifier]);
    for (var i = 0; i < ret.length; i++) {
      var processedName = iterations[1].variablesResolverPosition.last;
      var a =
          _recursivelyProcessed(iterations.sublist(1), hasName, name, ret[i]);
      ret[i][processedName] = a;
    }
    return ret;
  } else {
    var ret = <Map<String, dynamic>>[];
    var iteration = List.from(
        submap == null ? iterations.single.iteration : submap[mapIdentifier]);
    for (var map in iteration) {
      var retMap = Map<String, dynamic>.from(map);
      retMap[hasName] = _processStoreValue(map[name]);
      ret.add(retMap);
    }
    return ret;
  }
}

/// The mustache iterations are formed with a list of maps: e.g.:
/// {{#list}} {{mapItem}} {{#mapList}} {{element}} {{/mapList}} {{/list}}
/// represents a List list = \[ {"mapItem": item, "mapList": \[ {"element":1}, {"element":"2"} \]}, {"mapItem": item2, "mapList": \[ {"element":1}, {"element":"2"} \]}\]
/// Which means that there are several mapList lists, one in each list's map element
/// So this class is made to simplify the manipulation of those elements,
/// which consists of lists of maps that can be easily manipulated with the
/// methods here provided, if so needed
class _MustacheIteration {
  /// The iteration object
  List<Map> iteration;

  /// A series of names that represents the mustache tags iterated
  /// to reach the List<Map> iteration object
  List<String> variablesResolverPosition;

  _MustacheIteration(this.iteration, this.variablesResolverPosition);

  /// Saves `value` in every element of iteration in the `key` position
  /// and returns the result of doing so
  List<Map> setAll(String key, dynamic value) {
    var ret = [];
    for (var e in iteration) {
      e[key] = value;
      ret.add(e);
    }
    iteration = ret.cast<Map>();
    return ret;
  }
}
