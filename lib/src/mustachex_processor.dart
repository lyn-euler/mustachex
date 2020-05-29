import 'dart:async';

import 'package:mustache_template/mustache.dart';
import 'package:mustache_recase/mustache_recase.dart' as mustache_recase;
import 'package:mustachex/src/variable_recase_decomposer.dart';
import 'package:mustachex/src/variables_resolver.dart';
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
    return Template(
        partialsResolver(MissingPartialException(partialName: name)));
  }

  Map<String, dynamic> _mustacheVars(String source) {
    var template = Template(source, partialResolver: _partialsResolverAdapted);
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
      } else if (error.message.startsWith('Partial not found')) {
        throw MissingPartialException(templateException: error);
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
            var sectionSourceTemplate =
                Template(contents, partialResolver: _partialsResolverAdapted);
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
                  _recursivelyProcessHasX(iterations, variable, recasedName);
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
              variablesResolver[storeLocation] =
                  _processHasXStoringValue(storedVar);
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
          dynamic preExistentVar;
          try {
            preExistentVar =
                variablesResolver.get(ex.parentCollectionsWithVarName);
          } on VarFromListRequestException catch (listException) {
            // //recasea cada item (si está) y vuelve a guardar con el cambio
            // List parent = variablesResolver[listException.parentCollections];
            // parent.forEach((items) {
            //   var variable = items[ex.varName];
            //   if (variable is StringVariable) {
            //     items[ex.request] = variable[ex.recasing];
            //   } else {
            //     throw UnsupportedError(
            //         'You are trying to recase a ${variable.runtimeType} type.\n'
            //         '"${ex.parentCollectionsWithRequest.join('.')}" should be a String instead.');
            //   }
            // });
            // variablesResolver[listException.parentCollections] = parent;
            // return _tryRender();
            //recasea cada item (si está) y vuelve a guardar con el cambio
            var iteration =
                _getPrimigenicMustacheIteration(ex, listException.request.last);
            var mapToReplace = iteration.variablesResolverPosition.first;
            variablesResolver[mapToReplace] =
                _recursivelyProcessRecasing(iteration, ex);
            return _tryRender();
          }
          if (preExistentVar != null) {
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

  _MustacheIteration _getPrimigenicMustacheIteration(
      _MustacheMissingException e, String recasedName) {
    var collection = e.parentCollections.first;
    var resolvedVar = variablesResolver[collection];
    return _MustacheIteration(resolvedVar.cast<Map>(), [collection]);
    // if (resolvedVar is List) {
    //   if (resolvedVar.every((e) => e is Map)) {
    //     return _MustacheIteration(resolvedVar.cast<Map>(), [collection]);
    //   } else {
    //     _throwImpossibleState();
    //   }
    // }
  }

  /// procesa las _MustacheIterations que encuentra según la exepción
  List<_MustacheIteration> _getMustacheIterations(
      _MustacheMissingException e, String recasedName) {
    var iterations = <_MustacheIteration>[];
    var request = <String>[];
    var elements = List.from(e.parentCollections);
    // elements.add(recasedName);
    var resolvedVar;
    for (String collection in elements) {
      request.add(collection);
      try {
        resolvedVar = variablesResolver[request];
      } on VarFromListRequestException {
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
  String partialName;
  final TemplateException templateException;
  MissingPartialException({this.templateException, this.partialName}) {
    partialName ??= templateException.message
        .substring(19, templateException.message.length - 1);
  }

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

  @override
  String toString() => 'Should process {{${_d.request}}} but lacks both '
      'the value for "${_d.varName}" and the function to fulfill missing values.';
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

  @override
  String toString() {
    var ret = 'Missing section tag "{{#$request}}"';
    if (parentCollections.isEmpty) {
      ret += ', from $humanReadableVariable';
    }
    return ret;
  }
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
bool _processHasXStoringValue(storedVar) {
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
List<Map> _recursivelyProcessHasX(
    List<_MustacheIteration> iterations, String hasName, String name,
    [Map submap]) {
  var mapIdentifier = iterations.first.variablesResolverPosition.last;
  if (iterations.length > 1) {
    var ret = List<Map>.from(
        submap == null ? iterations.first.iteration : submap[mapIdentifier]);
    for (var i = 0; i < ret.length; i++) {
      var processedName = iterations[1].variablesResolverPosition.last;
      var a =
          _recursivelyProcessHasX(iterations.sublist(1), hasName, name, ret[i]);
      ret[i][processedName] = a;
    }
    return ret;
  } else {
    var ret = <Map<String, dynamic>>[];
    var iteration = List.from(
        submap == null ? iterations.single.iteration : submap[mapIdentifier]);
    for (var map in iteration) {
      var retMap = Map<String, dynamic>.from(map);
      retMap[hasName] = _processHasXStoringValue(map[name]);
      ret.add(retMap);
    }
    return ret;
  }
}

class MissingNestedVariable {
  final MissingVariableException e;

  MissingNestedVariable(this.e);

  @override
  String toString() =>
      "Can't recase ${e.parentCollectionsWithRequest.join('->')} because there is no '${e.varName}' value to recase. Maybe a typo?";
}

/// Las iterations son los valores de los primeros List<Map> del varsResolver
/// el exeption es la data del recasing que falta hacer
/// Esta función devuelve el map más primigenio de las iterations con
/// los valores del recasing faltantes agregados en donde corresponde
/// (en los maps del menos primigenio)
List<Map> _recursivelyProcessRecasing(
    _MustacheIteration iteration, MissingVariableException e,
    [Map submap]) {
  List<Map> _recursiveRecaseAssignment(List<Map> mapas, List<String> keys) {
    if (keys.isEmpty) {
      for (var map in mapas) {
        //se guarda el recasing
        try {
          map[e.request] = map[e.varName][e.recasing];
        } on NoSuchMethodError {
          //trató de recasear algo q dio null, debe faltar
          throw MissingNestedVariable(e);
        }
      }
      return mapas;
      // } else if (keys.length == 1) {
      //   for (var map in mapas) {
      //     //se guarda el recasing
      //     map[keys.single][e.request] = map[keys.single][e.varName][e.recasing];
      //   }
      //   return mapas;
    } else {
      for (var map in mapas) {
        if (map[keys.first] != null) {
          map[keys.first] = _recursiveRecaseAssignment(
              List<Map>.from(map[keys.first]), keys.sublist(1));
        }
      }
      return mapas;
    }
  }

  // los iterations tienen [{},{},{},...]
  var ret = <Map>[];
  var parentCollectionsKeys = e.parentCollections.sublist(1);
  ret.addAll(
      _recursiveRecaseAssignment(iteration.iteration, parentCollectionsKeys));
  return ret;

  /// Devuelve un map sacado de la primera iteración con todos sus elementos
  /// procesados para devolver sus últimas instancias con un field `request`
  /// con el recaseo apropiado de `varName`
  // var mapIdentifier = iterations.first.variablesResolverPosition.last;
  // if (iterations.length > 1) {
  //   //ir al caso base
  //   var ret = List<Map>.from(
  //       submap == null ? iterations.first.iteration : submap[mapIdentifier]);
  //   for (var i = 0; i < ret.length; i++) {
  //     var processedName = iterations[1].variablesResolverPosition.last;
  //     var a = _recursivelyProcessRecasing(iterations.sublist(1), e, ret[i]);
  //     ret[i][processedName] = a;
  //   }
  //   return ret;
  // } else {
  //   var ret = <Map<String, dynamic>>[];
  //   var iteration = List.from(
  //       submap == null ? iterations.single.iteration : submap[mapIdentifier]);
  //   for (var map in iteration) {
  //     var retMap = Map<String, dynamic>.from(map);
  //     var variable = map[d.varName];
  //     if (variable != null) {
  //       retMap[d.request] = variable[d.recasing];
  //     } else
  //       debugger();
  //     ret.add(retMap);
  //   }
  //   return ret;
  // }
}

typedef ValueProcessFunc = dynamic Function(dynamic);

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
  List<Map> setAll(
      String assignmentKey, String valueKey, ValueProcessFunc func) {
    var ret = <Map>[];
    for (var e in iteration) {
      e[assignmentKey] = func(e[valueKey]);
      ret.add(e);
    }
    return ret;
  }
}
