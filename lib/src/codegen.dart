// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/** Collects common snippets of generated code. */
library codegen;

import 'file_system/path.dart';
import 'info.dart';
import 'utils.dart';

/**
 * Header with common imports, used in every generated .dart file.  If path is
 * null then there is no file associated with the template (used by testing
 * so we'll display <MEMORY> for file name.
 */
String header(Path path, String libraryName) => """
// Auto-generated from ${path != null ? path.filename : "<MEMORY>"}.
// DO NOT EDIT.

library $libraryName;

$imports
""";

// TODO(sigmund): include only those imports that are used by the code.
String get imports => """
import 'dart:html' as autogenerated_html;
import 'dart:web_audio' as autogenerated_audio;
import 'dart:svg' as autogenerated_svg;
import 'package:web_components/web_components.dart' as autogenerated;
""";

/** The code in .dart files generated for a web component. */
// TODO(sigmund): omit [_root] if the user already defined it.
String componentCode(
    String className,
    String extraFields,
    String createdBody,
    String insertedBody,
    String removedBody) => """
  /** Autogenerated from the template. */

  /**
   * Shadow root for this component. We use 'var' to allow simulating shadow DOM
   * on browsers that don't support this feature.
   */
  var _root;
$extraFields

  $className.forElement(e) : super.forElement(e);

  void created_autogenerated() {
$createdBody
  }

  void inserted_autogenerated() {
$insertedBody
  }

  void removed_autogenerated() {
$removedBody
  }

  /** Original code from the component. */
""";

/**
 * Top-level initialization code. This is the bulk of the code in the
 * main.html.dart generated file if the user inlined his code in the page, or
 * code appended to the main entry point .dart file, if the user specified an
 * enternal file in the top-level script tag.
 */
String mainDartCode(
    String originalCode,
    String topLevelFields,
    String fieldInitializers,
    String modelBinding) => """

// Original code
$originalCode

// Additional generated code
/** Create the views and bind them to models. */
void init_autogenerated() {
  var _root = autogenerated_html.document.body;
$topLevelFields

  // Initialize fields.
$fieldInitializers
  // Attach model to views.
$modelBinding
}
""";

/**
 * The code that will be used to bootstrap the application, this is inlined in
 * the main.html.html output file.
 */
String bootstrapCode(Path userMainImport) => """
library bootstrap;

import '$userMainImport' as userMain;

main() {
  userMain.main();
  userMain.init_autogenerated();
}
""";

/**
 * Code generated to wrap all components defined in a single HTML into a single
 * library.
 */
String wrapComponentsLibrary(FileInfo info, List<Path> exports) => """
// Auto-generated from ${info.path}.
// DO NOT EDIT.

library ${info.libraryName};

${exportList(exports)}
""";

/** Generate text for a list of imports. */
String importList(List<Path> imports) =>
  Strings.join(imports.map((url) => "import '$url';"), '\n');

/** Generate text for a list of export. */
String exportList(List<Path> exports) =>
  Strings.join(exports.map((url) => "export '$url';"), '\n');

/**
 * Text corresponding to a directive, fixed in case the code is in a different
 * output location.
 */
String directiveText(
    DartDirectiveInfo directive, LibraryInfo src, PathInfo pathInfo) {
  var buff = new StringBuffer();
  var uri = pathInfo.transformUrl(src, directive.uri);
  buff.add(directive.label)
      .add(" '")
      .add(uri.replaceAll("'", "\\'"))
      .add("'");
  if (directive.prefix != null) {
    buff.add(' as ')
        .add(directive.prefix);
  }
  if (directive.show != null) {
    buff.add(' show ')
        .add(Strings.join(directive.show, ','));
  }
  if (directive.hide != null) {
    buff.add(' hide ')
        .add(Strings.join(directive.hide, ','));
  }
  buff.add(';');
  return buff.toString();
}
