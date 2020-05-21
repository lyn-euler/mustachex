/// A decompositor of recased variable requests.
/// Given a `request`, it's automatically decomposed from the
/// "`varName`(_`recasing`)?" format
class VariableRecaseDecomposer {
  String _varName;
  String _recasing;
  final String _request;

  VariableRecaseDecomposer(this._request) {
    if (_request.contains(RegExp(r'(.c|Case)$'))) {
      var casingAnalyzer = RegExp(r'(\w+)_([A-Za-z]{2,})$');
      Match match = casingAnalyzer.firstMatch(_request);
      _varName = match.group(1);
      _recasing = match.group(2);
    } else {
      _varName = _request;
    }
  }

  String get request => _request;
  String get varName => _varName;
  String get recasing => _recasing;
}
