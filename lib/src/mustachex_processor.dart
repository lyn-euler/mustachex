import 'package:mustache/mustache.dart';
import 'package:mustache_recase/mustache_recase.dart' as mustache_recase;
import 'package:mustachex/src/variables_resolver.dart';

class MissingPartialException implements Exception {
  final String partialName;
  MissingPartialException(this.partialName);

  String toString() => "Missing partial: Partial '$partialName' not found";
}

/// Acá guardás una cache para eficientizar las ejecuciones del processMustacheThrowingIfAbsent
/// que se ejecuta con lo mismo varias veces
Map<String, Map> _sourceCache = {};

typedef Template PartialsResolver(String);

/// Processes a mustache formatted source with the given variables and throws
/// [MustacheMissingException] whenever any of them is missing
String processMustacheThrowingIfAbsent(String source, Map resolverVars,
    {PartialsResolver partialsResolver}) {
  if (_sourceCache[source] == null) {
    _sourceCache[source] = {
      "template": Template(source,
          partialResolver: partialsResolver, htmlEscapeValues: false),
      "variables": mustacheVars(source)
    };
  }
  Template template = _sourceCache[source]["template"];
  Map variables = _sourceCache[source]["variables"];
  Map vars = Map.from(resolverVars);
  vars.addAll(mustache_recase.cases);
  try {
    return template.renderString(vars);
  } on TemplateException catch (e) {
    if (e.message.contains("section tag")) {
      throw MissingSectionTagException(e, variables);
    } else if (e.message.contains("variable tag")) {
      throw MissingVariableException(e, variables);
    } else {
      throw UnsupportedError("Don't know what the heck is this: $e");
    }
  }
}

/// Indicates that the `request` value wasn't provided
/// Note that `request` is automatically decomposed from `varName`(_`recasing`)?
class MissingVariableException extends MustacheMissingException {
  VariableRecaseDecomposer _d;
  List<String> _parentCollections;

  MissingVariableException(TemplateException e, Map sourceVariables)
      : super(
            e.message.substring(36, e.message.length - 1), e, sourceVariables);
}

/// Indicates that the `request` value wasn't provided
/// Note that `request` is automatically decomposed from `varName`(_`recasing`)?
class MissingSectionTagException extends MustacheMissingException {
  VariableRecaseDecomposer _d;
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
    this._d = VariableRecaseDecomposer(missing);
    String sourceBefore = e.source.substring(0, e.offset);
    //cambiar las variables si estás en un {{#mapa|lista}}
    this._parentCollections = _processParentMaps(sourceBefore) ?? [];
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

  String get request => _d.request;
  String get varName => _d.varName;
  String get recasing => _d.recasing;

  /// The maps that contains the missing value. For example, \[a,b\] means that
  /// the missing variable with `varName` 'missing' should be stored in
  /// variablesResolver\["a"\]\["b"\]\["missing"\]
  List<String> get parentCollections => _parentCollections;

  /// Same as `parentCollections` but with the varName added at the end
  List<String> get parentCollectionsWithVarName {
    List<String> vals = List.from(_parentCollections);
    vals.add(_d.varName);
    return vals;
  }

  /// for logging or informing the user wchich variable is missing beneath maps
  String get humanReadableVariable {
    String ret = parentCollectionsWithVarName.join("'],['");
    if (parentCollectionsWithVarName.length > 1) {
      ret = "['$ret']";
    }
    return ret;
  }

  /// Same as `parentCollections` but with the request added at the end
  List<String> get parentCollectionsWithRequest {
    List<String> vals = List.from(_parentCollections);
    vals.add(_d.request);
    return vals;
  }

  /// usado para scanear el código mustache por tokens que nombren a los maps
  RegExp _beginToken = RegExp(r"{{ ?# ?(.*?)}}"),
      _endToken = RegExp(r"{{ ?\/ ?(.*?)}}");

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
  Template template = Template(source);
  return gatherTemplateRequiredVars(template);
}

Map<String, dynamic> gatherTemplateRequiredVars(Template template,
    [Map<String, dynamic> variables]) {
  Map<String, dynamic> vars = variables ?? <String, dynamic>{};
  RegExp nameRegExp = RegExp(r": (.*).$");
  while (true) {
    TemplateException error = _failing_gathering(template, vars);
    // , printMessage: true, printReturn: true);
    if (error == null)
      return vars;
    else {
      String e = error.message;
      String name = nameRegExp.firstMatch(e).group(1);
      if (e.contains("for variable tag")) {
        vars[name] = "%ValueOf$name%";
      } else {
        //up to this version, if not a variable, only a Section is possible
        RegExp inSectionSrc = RegExp("{{([#^])$name}}([\\s\\S]*?){{/$name}}");
        List<Match> matches = inSectionSrc.allMatches(error.source).toList();
        for (int i = 0; i < matches.length; i++) {
          String type = matches[i].group(1);
          String contents = matches[i].group(2);
          Template sectionSourceTemplate = Template(contents);
          // if (e.contains("for inverse section")) {
          // } else if (e.contains("for section")) {
          if (type == '^') {
            //inverse section
            vars["^$name"] ??= {};
            vars["^$name"]
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
    Map variables = Map.from(vars);
    variables.addAll(mustache_recase.cases);
    String ret = template.renderString(variables);
    if (printReturn) print(ret);
    return null;
  } on TemplateException catch (e) {
    if (printMessage) print(e.message);
    return e;
  }
}
