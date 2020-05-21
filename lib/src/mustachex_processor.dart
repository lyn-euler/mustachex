import 'package:mustache/mustache.dart';
import 'package:mustache_recase/mustache_recase.dart' as mustache_recase;
import 'package:mustachex/src/variable_recase_decomposer.dart';

_tryExecution({bool answer, String relativePathResolved}) {
  var ending;
  try {
    if (answer == null && null == relativePathResolved)
      ending = executionLogic();
    else
      ending = this.executionLogic(
          askIfOverridingAnswer: answer,
          relativePathResolved: relativePathResolved);
    // } on UnresolvedUriException catch (e) {
    //   Isolate.resolvePackageUri(e.uri).then((Uri uri) {
    //     _execute(relativePathResolved: uri.path);
    //   });
    //   return null;
  } on MightAskIfOverridingException catch (e) {
    logger.finer("There is an overriding situation where the policy is to ask."
        " Asking...");
    runner.askForConfirmation(e.message).then((bool answer) {
      _tryExecution(answer: answer);
    });
    return null;
    // } on MissingPartialException catch (e) {
    //   logger.finer(
    //       "Needing to resolve ${e.partialName} (already tried in generator_plus package: ${e.original_package_searched})");
    //   if (e.original_package_searched) rethrow;
    //   resolvePath("package:generator_plus/src").then((String path) {
    //     original_package_path =
    //         path.substring(0, path.length - 7); //from src/common.dart
    //     logger.fine("mustache_partials dir resolved to $original_package_path");
    //     _tryExecution();
    //   });
    //   return null;
  } on MissingSectionTagException catch (e, st) {
    logger.finer(
        "There is a missing value for '${e.humanReadableVariable}' mustache "
        "section tag. Trying to solve this...");
    //Primero nos fijamos si es una guarda tipo hasXxxYyyyyyZzzz
    String variable = e.request;
    if (variable.startsWith("has")) {
      String recasedName = ReCase(variable.substring(3)).camelCase;
      List<_MustacheIteration> iterations =
          _getMustacheIterations(e, recasedName);
      if (iterations.isNotEmpty) {
        var mapToReplace = iterations.first.variablesResolverPosition.first;
        var assign = _recursivelyProcessed(iterations, variable, recasedName);
        variablesResolver[mapToReplace] = assign;
        logger.finest("Problem solved by setting all intances of "
            "the last submap with a '$variable' field saying wether "
            "the field '$recasedName' is set or not.");
      } else {
        var request = e.parentCollections;
        var storeLocation = List.from(request);
        request.add(recasedName);
        storeLocation.add(variable);
        var storedVar = variablesResolver.get(request);
        variablesResolver[storeLocation] = _processStoreValue(storedVar);
        logger.finest("Problem solved by defining "
            "'$variable' to ${variablesResolver[storeLocation]}");
      }
      _tryExecution();
      return null;
    } else {
      //No es del tipo hasXxxYyy. Le falta la lista directamente
      _completer.completeError(e, st);
      return null;
    }
  } on MissingVariableException catch (e) {
    logger.finer(
        "There is a missing value for '${e.humanReadableVariable}' mustache "
        "variable. Trying to solve this...");
    //Primero nos fijamos si falta el valor o sólo hay que recasearlo
    dynamic recasingAttempt =
        variablesResolver.get(e.parentCollectionsWithVarName);
    if (recasingAttempt != null) {
      variablesResolver[e.parentCollectionsWithRequest] =
          variablesResolver.get(e.parentCollectionsWithRequest);
      logger.finest("Problem solved by recasing it to '$recasingAttempt'");
      _tryExecution();
      return null;
    } else {
      /* TODO(baja prioridad): Meter el handleVar acá en vez de esa mierda.
              La macana es que está definido en GeneratorImpl y de acá no llegamos a eso.
              Sumale que hay que manejarlo como la variable definida localmente en el generador
              específico */
      runner
          .askForInput(
              "Please provide the value for the missing variable '${e.varName}'")
          .then((String value) {
        variablesResolver[e.parentCollectionsWithVarName] = value;
        logger.finest("Problem solved by asking user ('$value' answered)");
        _tryExecution();
      });
      return null;
    }
  } catch (e, st) {
    // debugger();
    _completer.completeError(e, st);
    return null;
  }
  _completer.complete((ending is Future) ? ending : Future.value(ending));
}

List<_MustacheIteration> _getMustacheIterations(
    MissingSectionTagException e, String recasedName) {
  List<_MustacheIteration> iterations = [];
  List<String> request = [];
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

class MissingPartialException implements Exception {
  final String partialName;
  MissingPartialException(this.partialName);

  @override
  String toString() => "Missing partial: Partial '$partialName' not found";
}

/// Acá guardás una cache para eficientizar las ejecuciones del processMustacheThrowingIfAbsent
/// que se ejecuta con lo mismo varias veces
Map<String, Map> _sourceCache = {};

typedef PartialsResolver = Template Function(String partialName);

/// Processes a mustache formatted source with the given variables and throws
/// [MustacheMissingException] whenever any of them is missing
String processMustacheThrowingIfAbsent(String source, Map resolverVars,
    {PartialsResolver partialsResolver}) {
  if (_sourceCache[source] == null) {
    _sourceCache[source] = {
      'template': Template(source,
          partialResolver: partialsResolver, htmlEscapeValues: false),
      'variables': mustacheVars(source)
    };
  }
  Template template = _sourceCache[source]['template'];
  Map variables = _sourceCache[source]['variables'];
  var vars = Map.from(resolverVars);
  vars.addAll(mustache_recase.cases);
  try {
    return template.renderString(vars);
  } on TemplateException catch (e) {
    if (e.message.contains('section tag')) {
      throw MissingSectionTagException(e, variables);
    } else if (e.message.contains('variable tag')) {
      throw MissingVariableException(e, variables);
    } else {
      throw UnsupportedError("Don't know what the heck is this: $e");
    }
  }
}

/// Indicates that the `request` value wasn't provided
/// Note that `request` is automatically decomposed from `varName`(_`recasing`)?
class MissingVariableException extends MustacheMissingException {
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
class MissingSectionTagException extends MustacheMissingException {
  @override
  VariableRecaseDecomposer _d;
  @override
  List<String> _parentCollections;

  MissingSectionTagException(TemplateException e, Map sourceVariables)
      : super(
            e.message.substring(35, e.message.length - 1), e, sourceVariables);
}

/// The parent class that does the computations
class MustacheMissingException {
  VariableRecaseDecomposer _d;
  List<String> _parentCollections;

  MustacheMissingException(
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

Map<String, dynamic> mustacheVars(String source) {
  var template = Template(source);
  return gatherTemplateRequiredVars(template);
}

Map<String, dynamic> gatherTemplateRequiredVars(Template template,
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
                .addAll(gatherTemplateRequiredVars(sectionSourceTemplate));
          } else {
            vars[name] ??= {};
            vars[name]
                .addAll(gatherTemplateRequiredVars(sectionSourceTemplate));
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
