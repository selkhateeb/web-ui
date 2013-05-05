// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/** Collects several code emitters for the template tool. */
library emitters;

import 'dart:uri';
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';
import 'package:html5lib/dom.dart';
import 'package:html5lib/dom_parsing.dart';
import 'package:html5lib/parser.dart';
import 'package:source_maps/span.dart' show Span, FileLocation;

import 'code_printer.dart';
import 'codegen.dart' as codegen;
import 'dart_parser.dart' show DartCodeInfo;
import 'html5_utils.dart';
import 'html_css_fixup.dart';
import 'info.dart';
import 'messages.dart';
import 'paths.dart';
import 'refactor.dart';
import 'utils.dart';

/**
 * Context used by an emitter. Typically representing where to generate code
 * and additional information, such as total number of generated identifiers.
 */
class Context {
  final Declarations declarations;
  final Declarations statics;
  final CodePrinter printer;
  final bool isClass;

  Context({Declarations declarations, Declarations statics,
           CodePrinter printer, bool isClass: false, int indent: 0})
      : this.declarations = declarations != null
            ? declarations : new Declarations(indent, isLocal: !isClass),
        this.statics = statics != null
            ? statics : new Declarations(indent, staticKeyword: isClass),
        this.isClass = isClass,
        this.printer = printer != null
            ? printer : new CodePrinter(isClass ? indent + 1 : indent);
}

/**
 * Generates a field for any element that has either event listeners or data
 * bindings.
 */
void emitDeclarations(ElementInfo info, Declarations declarations) {
  if (!info.isRoot) {
    var type = (info.node.namespace == 'http://www.w3.org/2000/svg')
        ? 'autogenerated_svg.SvgElement'
        : 'autogenerated.${typeForHtmlTag(info.node.tagName)}';
    declarations.add(type, info.identifier, info.node.sourceSpan);
  }
}

/** Initializes fields and variables pointing to a HTML element.  */
void emitInitializations(ElementInfo info,
    Context context, CodePrinter childrenPrinter) {
  var printer = context.printer;
  var id = info.identifier;
  if (info.createdInCode) {
    printer.addLine("$id = ${_emitCreateHtml(info.node, context.statics)};",
        span: info.node.sourceSpan);
  } else if (!info.isRoot) {
    var parent = info.parent;
    while (parent != null && parent.identifier == null) {
      parent = parent.parent;
    }
    compilerAssert(parent != null, 'If isRoot is false, we should always have'
        ' a parent info that is root.');

    // Note: we rely on the assumption that we are essentially indexing into a
    // static HTML fragment. It has not been modified at the point where we are
    // accessing a node from it. This allows us to rely on the path.
    compilerAssert(!parent.childrenCreatedInCode,
        'Parent should be a static HTML fragment.');

    var path = _computeNodePath(info.node, parent.node);
    var pathExpr = path.map((p) => '.nodes[$p]').join();

    printer.addLine("$id = ${parent.identifier}$pathExpr;",
        span: info.node.sourceSpan);
  }

  printer.add(childrenPrinter);

  if (info.childrenCreatedInCode && !info.hasLoop && !info.hasCondition) {
    _emitAddNodes(printer, context.statics, info.children, '$id.nodes');
  }
}

/**
 * Returns the path of the node from the provided root element. For example,
 * given a tree like:
 *
 *     <a><b></b><c><d></d></c></a>
 *
 * The path of "d" starting from "a" would be: `[1, 0]`. In other words, we can
 * get "d" like this:
 *
 *     var d = a.nodes[1].nodes[0];
 *
 * Note that we rely on the
 */
List<int> _computeNodePath(Node node, Node root) {
  // We need to be extra careful because if you manipulate the DOM, it won't
  // necessarily parse back into the same structure:
  // http://www.whatwg.org/specs/web-apps/current-work/multipage/the-end.html#html-fragment-serialization-algorithm
  // Since our manipulations are generally just removing things, I think we only
  // need to deal with text nodes (adjacent and empty).

  var path = [];
  for (var n = node; n != root; n = n.parent) {
    // TODO(jmesserly): this is linear, and could end up causing an O(N^2)
    // compiler behavior in the aggregate if you had a node with lots of
    // children and they each needed paths computed.
    // We could avoid the N^2 in the compiler by caching the node's index, but
    // since we can't directly store it on the node, it seems too complex and
    // would make the typical case worse.

    int index = 0;
    var previous = null;
    for (var child in n.parent.nodes) {
      if (child == n) break;

      if (child is Text) {
        // Ignore empty text nodes and text nodes following other text nodes.
        // These nodes will not be created by the HTML parser.
        if (child.value == '' || previous is Text) continue;
      }

      index++;
      previous = child;
    }

    path.add(index);
  }
  return path.reversed.toList();
}

/**
 * Emit statements that add 1 or more HTML nodes directly as children of
 * [target] (which can be a template or another node.
 */
_emitAddNodes(CodePrinter printer, Declarations statics, List<NodeInfo> nodes,
    String target) {

  String createChildExpression(NodeInfo info) {
    if (info.identifier != null) return info.identifier;
    return _emitCreateHtml(info.node, statics);
  }

  if (nodes.length == 1) {
    printer.addLine("$target.add(${createChildExpression(nodes.single)});");
  } else if (nodes.length > 0) {
    printer..insertIndent()
        ..add("$target.addAll([")
        ..indent += 2;
    for (int i = 0; i < nodes.length; i++) {
      var exp = createChildExpression(nodes[i]);
      if (i > 0) printer.insertIndent();
      printer..add(exp, span: nodes[i].node.sourceSpan)
          ..add(i == nodes.length - 1 ? ']);\n' : ',\n');
    }
    printer.indent -= 2;
  }
}

/**
 * Generates event listeners attached to a node and code that attaches/detaches
 * the listener.
 */
void emitEventListeners(ElementInfo info, CodePrinter printer) {
  var id = info.identifier;
  info.events.forEach((name, events) {
    for (var event in events) {
      // Note: the name $event is from AngularJS and is essentially public
      // API. See issue #175.
      // TODO(sigmund): update when we track spans for each attribute separately
      printer.addLine('__t.listen($id.${event.streamName},'
          ' (\$event) { ${event.action(id)}; });', span: info.node.sourceSpan);
    }
  });
}

/** Emits attributes with some form of data-binding. */
void emitAttributeBindings(ElementInfo info, CodePrinter printer) {
  info.attributes.forEach((name, attr) {
    if (attr.isClass) {
      _emitClassAttributeBinding(info.identifier, attr, printer,
          info.node.sourceSpan);
    } else if (attr.isStyle) {
      _emitStyleAttributeBinding(info.identifier, attr, printer,
          info.node.sourceSpan);
    } else if (attr.isSimple) {
      _emitSimpleAttributeBinding(info, name, attr, printer);
    } else if (attr.isText) {
      _emitTextAttributeBinding(info, name, attr, printer);
    }
  });
}

// TODO(sigmund): extract the span from attr when it's available
void _emitClassAttributeBinding(
    String identifier, AttributeInfo attr, CodePrinter printer, Span span) {
  for (var binding in attr.bindings) {
    printer.addLine(
        '__t.bindClass($identifier, () => ${binding.exp}, ${binding.isFinal});',
        span: span);
  }
}

void _emitStyleAttributeBinding(
    String identifier, AttributeInfo attr, CodePrinter printer, Span span) {
  var exp = attr.boundValue;
  var isFinal = attr.isBindingFinal;
  printer.addLine('__t.bindStyle($identifier, () => $exp, $isFinal);',
      span: span);
}

void _emitSimpleAttributeBinding(ElementInfo info,
    String name, AttributeInfo attr, CodePrinter printer) {
  var node = info.identifier;
  var binding = attr.boundValue;
  var isFinal = attr.isBindingFinal;
  var field = findDomField(info, name);
  var isUrl = urlAttributes.contains(name);
  printer.addLine('__t.oneWayBind(() => $binding, '
        '(e) { if ($node.$field != e) $node.$field = e; }, $isFinal, $isUrl);',
      span: info.node.sourceSpan);
  if (attr.customTwoWayBinding) {
    printer.addLine('__t.oneWayBind(() => ${info.identifier}.$field, '
          '(__e) { $binding = __e; }, false);');
  }
}

void _emitTextAttributeBinding(ElementInfo info,
    String name, AttributeInfo attr, CodePrinter printer) {
  var textContent = attr.textContent.map(escapeDartString).toList();
  var setter = findDomField(info, name);
  var content = new StringBuffer();
  var binding;
  var isFinal;
  if (attr.bindings.length == 0) {
    // Constant attribute passed to initialize a web component field. If the
    // attribute is a normal DOM attribute, we don't need to do anything.
    if (!setter.startsWith('xtag.')) return;
    assert(textContent.length == 1);
    content.write(textContent[0]);
    isFinal = true;
  } else if (attr.bindings.length == 1) {
    binding = attr.boundValue;
    isFinal = attr.isBindingFinal;
    content..write(textContent[0])
        ..write('\${__e.newValue}')
        ..write(textContent[1]);
  } else {
    // TODO(jmesserly): we could probably do something faster than a list
    // for watching on multiple bindings.
    binding = '[${attr.bindings.map((b) => b.exp).join(", ")}]';
    isFinal = attr.bindings.every((b) => b.isFinal);

    for (int i = 0; i < attr.bindings.length; i++) {
      content..write(textContent[i])..write("\${__e.newValue[$i]}");
    }
    content.write(textContent.last);
  }

  var exp = "'$content'";
  if (urlAttributes.contains(name)) {
    exp = 'autogenerated.sanitizeUri($exp)';
  }
  printer.addLine("__t.bind(() => $binding, "
      " (__e) { ${info.identifier}.$setter = $exp; }, $isFinal);",
      span: info.node.sourceSpan);

}

/** Generates watchers that listen on data changes and update text content. */
void emitContentDataBinding(TextInfo info, CodePrinter printer) {
  var exp = info.binding.exp;
  var isFinal = info.binding.isFinal;
  printer.addLine(
      'var ${info.identifier} = __t.contentBind(() => $exp, $isFinal);',
      span: info.node.sourceSpan);
}

/**
 * Emits code for web component instantiation. For example, if the source has:
 *
 *     <x-hello>John</x-hello>
 *
 * And the component has been defined as:
 *
 *    <element name="x-hello" extends="div" constructor="HelloComponent">
 *      <template>Hello, <content>!</template>
 *      <script type="application/dart"></script>
 *    </element>
 *
 * This will ensure that the Dart HelloComponent for `x-hello` is created and
 * attached to the appropriate DOM node.
 */
void emitComponentCreation(ElementInfo info, CodePrinter printer) {
  var component = info.component;
  if (component == null) return;
  var id = info.identifier;
  printer..addLine(
      '__t.component(new ${component.className}()..host = $id);',
      span: info.node.sourceSpan);
}

/**
 * Emits code for template conditionals like `<template instantiate="if test">`
 * or `<td template instantiate="if test">`.
 */
void emitConditional(TemplateInfo info, CodePrinter printer,
    Context childContext) {
  var cond = info.ifCondition;
  printer..addLine('__t.conditional(${info.identifier}, () => $cond, (__t) {',
                   span: info.node.sourceSpan)
      ..indent += 1
      ..add(childContext.declarations)
      ..add(childContext.printer)
      ..indent -= 1;
  _emitAddNodes(printer, childContext.statics, info.children, '__t');
  printer..addLine('});\n');
}

/**
 * Emits code for template lists like `<template iterate='item in items'>` or
 * `<td template repeat='item in items'>`.
 */
void emitLoop(TemplateInfo info, CodePrinter printer, Context childContext) {
  var id = info.identifier;
  var items = info.loopItems;
  var loopVar = info.loopVariable;

  var suffix = '';
  // TODO(jmesserly): remove this functionality after a grace period.
  if (!info.isTemplateElement && !info.isRepeat) suffix = 'IterateAttr';

  printer..addLine('__t.loop$suffix($id, () => $items, '
          '(\$list, \$index, __t) {', span: info.node.sourceSpan)
      ..indent += 1
      ..addLine('var $loopVar = \$list[\$index];')
      ..add(childContext.declarations)
      ..add(childContext.printer)
      ..indent -= 1;
  _emitAddNodes(printer, childContext.statics, info.children, '__t');
  printer.addLine('});');
}


/**
 * An visitor that applies [NodeFieldEmitter], [EventListenerEmitter],
 * [DataValueEmitter], [ConditionalEmitter], and
 * [ListEmitter] recursively on a DOM tree.
 */
class RecursiveEmitter extends InfoVisitor {
  final FileInfo _fileInfo;
  Context _context;

  RecursiveEmitter(this._fileInfo, this._context);

  // TODO(jmesserly): currently visiting of components declared in a file is
  // handled separately. Consider refactoring so the base visitor works for us.
  visitFileInfo(FileInfo info) => visit(info.bodyInfo);

  void visitElementInfo(ElementInfo info) {
    if (info.identifier == null) {
      // No need to emit code for this node.
      super.visitElementInfo(info);
      return;
    }

    var indent = _context.printer.indent;
    var childPrinter = new CodePrinter(indent);
    emitDeclarations(info, _context.declarations);
    emitInitializations(info, _context, childPrinter);
    emitEventListeners(info, _context.printer);
    emitAttributeBindings(info, _context.printer);
    emitComponentCreation(info, _context.printer);

    var childContext = null;
    if (info.hasCondition) {
      childContext = new Context(statics: _context.statics, indent: indent + 1);
      emitConditional(info, _context.printer, childContext);
    } else if (info.hasLoop) {
      childContext = new Context(statics: _context.statics, indent: indent + 1);
      emitLoop(info, _context.printer, childContext);
    } else {
      childContext = new Context(declarations: _context.declarations,
          statics: _context.statics, printer: childPrinter,
          isClass: _context.isClass);
    }

    // Invoke super to visit children.
    var oldContext = _context;
    _context = childContext;
    super.visitElementInfo(info);
    _context = oldContext;
  }

  void visitTextInfo(TextInfo info) {
    if (info.identifier != null) {
      emitContentDataBinding(info, _context.printer);
    }
    super.visitTextInfo(info);
  }
}

/**
 * Style sheet polyfill, each CSS class name referenced (selector) is prepended
 * with prefix_ (if prefix is non-null).
 */
class StyleSheetEmitter extends CssPrinter {
  final String _prefix;

  StyleSheetEmitter(this._prefix);

  void visitClassSelector(ClassSelector node) {
    if (_prefix == null) {
      super.visitClassSelector(node);
    } else {
      emit('.${_prefix}_${node.name}');
    }
  }

  void visitIdSelector(IdSelector node) {
    if (_prefix == null) {
      super.visitIdSelector(node);
    } else {
      emit('#${_prefix}_${node.name}');
    }
  }
}

/** Helper function to emit the contents of the style tag. */
String emitStyleSheet(StyleSheet ss, [String prefix]) =>
  ((new StyleSheetEmitter(prefix))..visitTree(ss, pretty: true)).toString();

/** Generates the class corresponding to a single web component. */
class WebComponentEmitter extends RecursiveEmitter {
  final Messages messages;

  WebComponentEmitter(FileInfo info, this.messages)
      : super(info, new Context(isClass: true, indent: 1));

  CodePrinter run(ComponentInfo info, PathMapper pathMapper,
      TextEditTransaction transaction) {
    var elemInfo = info.elemInfo;

    // TODO(terry): Eliminate when polyfill is the default.
    var cssPolyfill = messages.options.processCss;

    // elemInfo is pointing at template tag (no attributes).
    assert(elemInfo.node.tagName == 'element');
    for (var childInfo in elemInfo.children) {
      var node = childInfo.node;
      if (node.tagName == 'template') {
        elemInfo = childInfo;
        break;
      }
    }
    _context.declarations.add('autogenerated.Template', '__t',
        elemInfo.node.sourceSpan);

    if (info.element.attributes['apply-author-styles'] != null) {
      _context.printer.addLine('if (__root is autogenerated.ShadowRoot) '
          '__root.applyAuthorStyles = true;');
      // TODO(jmesserly): warn at runtime if apply-author-styles was not set,
      // and we don't have Shadow DOM support? In that case, styles won't have
      // proper encapsulation.
    }

    if (info.template != null && !elemInfo.childrenCreatedInCode) {
      // TODO(jmesserly): scoped styles probably don't work when
      // childrenCreatedInCode is true.
      if (!info.styleSheets.isEmpty && !cssPolyfill) {
        // TODO(jmesserly): csslib+html5lib should work together.  We shouldn't
        //                  need to call a different function to serialize CSS.
        //                  Calling innerHTML on a StyleElement should be
        //                  enought - like a real browser.  CSSOM and DOM
        //                  should work together in the same tree.
        // TODO(terry): Only one style tag per component.
        var styleSheet =
            '<style scoped>\n'
            '${emitStyleSheet(info.styleSheets[0])}'
            '\n</style>';
        var template = elemInfo.node;
        template.insertBefore(new Element.html(styleSheet),
            template.children[0]);
      }

      _context.statics.add('final', '__shadowTemplate',
          elemInfo.node.sourceSpan,
          "new autogenerated.DocumentFragment.html('''"
          "${escapeDartString(elemInfo.node.innerHtml, triple: true)}"
          "''')");
      _context.printer.addLine(
          "__root.nodes.add(__shadowTemplate.clone(true));");
    }

    visit(elemInfo);

    bool hasExtends = info.extendsComponent != null;
    var codeInfo = info.userCode;
    var classDecl = info.classDeclaration;
    if (classDecl == null) return null;

    if (transaction == null) {
      transaction = new TextEditTransaction(codeInfo.code, codeInfo.sourceFile);
    }

    // Expand the headers to include web_ui imports, unless they are already
    // present.
    var libraryName = (codeInfo.libraryName != null)
        ? codeInfo.libraryName
        : info.tagName.replaceAll(new RegExp('[-./]'), '_');
    var header = new CodePrinter(0);
    header.add(codegen.header(path.basename(info.declaringFile.inputPath),
        libraryName));
    emitImports(codeInfo, info, pathMapper, header);
    header.addLine('');
    transaction.edit(0, codeInfo.directivesEnd, header);

    var classBody = new CodePrinter(1)
        ..add('\n')
        ..addLine('/** Autogenerated from the template. */')
        ..addLine('')
        // TODO(terry): omit [_css] if the user already defined it.
        ..addLine('/** CSS class constants. */')
        ..addLine('${createCssSelectorsDefinition(info, cssPolyfill)}')
        ..addLine('')
        ..add(_context.statics)
        ..add(_context.declarations)
        ..addLine('')
        ..addLine('void created_autogenerated() {')
        ..addLine(hasExtends ? '  super.created_autogenerated();' : null)
        ..addLine('  var __root = createShadowRoot("${info.tagName}");')
        ..addLine('  __t = new autogenerated.Template(__root);')
        ..add(_context.printer)
        ..addLine('  __t.create();')
        ..addLine('}')
        ..addLine('')
        ..addLine('void inserted_autogenerated() {')
        ..addLine(hasExtends ? '  super.inserted_autogenerated();' : null)
        ..addLine('  __t.insert();')
        ..addLine('}')
        ..addLine('')
        ..addLine('void removed_autogenerated() {')
        ..addLine(hasExtends ? '  super.removed_autogenerated();' : null)
        ..addLine('  __t.remove();')
        ..add('  ')
        ..addLine(_clearFields(_context.declarations))
        ..addLine('}')
        ..addLine('')
        ..addLine('/** Original code from the component. */');

    var pos = classDecl.leftBracket.end;
    transaction.edit(pos, pos, classBody);

    // Emit all the code in a single printer, keeping track of source-maps.
    return transaction.commit();
  }
}

/** Generates the class corresponding to the main html page. */
class EntryPointEmitter extends RecursiveEmitter {

  EntryPointEmitter(FileInfo fileInfo)
      : super(fileInfo, new Context(indent: 1));

  CodePrinter run(PathMapper pathMapper, TextEditTransaction transaction,
      bool rewriteUrls) {

    var filePath = _fileInfo.inputPath;
    visit(_fileInfo.bodyInfo);

    var codeInfo = _fileInfo.userCode;
    if (codeInfo == null) {
      assert(transaction == null);
      codeInfo = new DartCodeInfo(null, null, [], 'main(){\n}', null);
    }

    if (transaction == null) {
      transaction = new TextEditTransaction(codeInfo.code, codeInfo.sourceFile);
    }

    var libraryName = codeInfo.libraryName != null
        ? codeInfo.libraryName : _fileInfo.libraryName;
    var header = new CodePrinter(0);
    header.add(codegen.header(path.basename(filePath), libraryName));
    emitImports(codeInfo, _fileInfo, pathMapper, header);
    header..addLine('')
          ..addLine('')
          ..addLine('// Original code');
    transaction.edit(0, codeInfo.directivesEnd, header);

    return (transaction.commit())
        ..addLine('')
        ..addLine('// Additional generated code')
        ..addLine('void init_autogenerated() {')
        ..indent += 1
        ..addLine('var __root = autogenerated.document.body;')
        ..add(_context.statics)
        ..add(_context.declarations)
        ..addLine('var __t = new autogenerated.Template(__root);')
        ..add(_context.printer)
        ..addLine('__t.create();')
        ..addLine('__t.insert();')
        ..indent -= 1
        ..addLine('}');
  }
}

void emitImports(DartCodeInfo codeInfo, LibraryInfo info, PathMapper pathMapper,
    CodePrinter printer) {
  var seenImports = new Set();
  addUnique(String importString, [location]) {
    if (!seenImports.contains(importString)) {
      printer.addLine(importString, location: location);
      seenImports.add(importString);
    }
  }

  // Add imports only for those components used by this component.
  info.usedComponents.keys.forEach(
      (c) => addUnique("import '${pathMapper.relativeUrl(info, c)}';"));

  if (info is ComponentInfo) {
    // Inject an import to the base component.
    var base = (info as ComponentInfo).extendsComponent;
    if (base != null) {
      addUnique("import '${pathMapper.relativeUrl(info, base)}';");
    }
  }

  // Add existing import, export, and part directives.
  var file = codeInfo.sourceFile;
  for (var d in codeInfo.directives) {
    addUnique(d.toString(), file != null ? file.location(d.offset) : null);
  }
}

/** Clears all fields in [declarations]. */
String _clearFields(Declarations declarations) {
  if (declarations.declarations.isEmpty) return '';
  var buff = new StringBuffer();
  for (var d in declarations.declarations) {
    buff.write('${d.name} = ');
  }
  buff.write('null;');
  return buff.toString();
}

/**
 * An (runtime) expression to create the [node]. It always includes the node's
 * attributes, but only includes children nodes if [includeChildren] is true.
 */
String _emitCreateHtml(Node node, Declarations statics) {
  if (node is Text) {
    return "new autogenerated.Text('${escapeDartString(node.value)}')";
  }

  // Namespace constants from:
  // http://dev.w3.org/html5/spec/namespaces.html#namespaces
  var isHtml = node.namespace == 'http://www.w3.org/1999/xhtml';
  var isSvg = node.namespace == 'http://www.w3.org/2000/svg';
  var isEmpty = node.attributes.length == 0 && node.nodes.length == 0;

  var constructor;
  // Generate precise types like "new ButtonElement()" if we can.
  if (isEmpty && isHtml) {
    constructor = htmlElementConstructors[node.tagName];
    if (constructor != null) {
      constructor = '$constructor()';
    } else {
      constructor = "Element.tag('${node.tagName}')";
    }
  } else if (isEmpty && isSvg) {
    constructor = "_svg.SvgElement.tag('${node.tagName}')";
  } else {
    // TODO(sigmund): does this work for the mathml namespace?
    var target = isSvg ? '_svg.SvgElement.svg' : 'Element.html';
    constructor = "$target('${escapeDartString(node.outerHtml)}')";
  }

  var expr = 'new autogenerated.$constructor';
  var varName = '__html${statics.declarations.length}';
  statics.add('final', varName, node.sourceSpan, expr);
  return '${varName}.clone(true)';
}

/** Trim down the html for the main html page. */
void transformMainHtml(Document document, FileInfo fileInfo,
    PathMapper pathMapper, bool hasCss, bool rewriteUrls, Messages messages) {

  var filePath = fileInfo.inputPath;

  bool dartLoaderFound = false;
  for (var tag in document.queryAll('script')) {
    var src = tag.attributes['src'];
    if (src != null && src.split('/').last == 'dart.js') {
      dartLoaderFound = true;
    }
    if (tag.attributes['type'] == 'application/dart') {
      tag.remove();
    } else if (src != null && rewriteUrls) {
      tag.attributes["src"] = pathMapper.transformUrl(filePath, src);
    }
  }
  for (var tag in document.queryAll('link')) {
    var href = tag.attributes['href'];
    var rel = tag.attributes['rel'];
    if (rel == 'component' || rel == 'components') {
      tag.remove();
    } else if (href != null && rewriteUrls && !hasCss) {
      // Only rewrite URL if rewrite on and we're not CSS polyfilling.
      tag.attributes['href'] = pathMapper.transformUrl(filePath, href);
    }
  }

  if (hasCss) {
    var newCss = pathMapper.mangle(path.basename(filePath), '.css', true);
    var linkElem = new Element.html(
        '<link rel="stylesheet" type="text/css" href="$newCss">');
    var head = document.head;
    head.insertBefore(linkElem,
        head.hasChildNodes() ? head.nodes.first : null);
  }

  var styles = document.queryAll('style');
  if (styles.length > 0) {
    var allCss = new StringBuffer();
    fileInfo.styleSheets.forEach((styleSheet) =>
        allCss.write(emitStyleSheet(styleSheet)));
    styles[0].nodes.clear();
    styles[0].nodes.add(new Text(allCss.toString()));
    for (var i = styles.length - 1; i > 0 ; i--) {
      styles[i].remove();
    }
  }

  // TODO(jmesserly): put this in the global CSS file?
  // http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/templates/index.html#css-additions
  document.head.nodes.insert(0, parseFragment(
      '<style>template { display: none; }</style>'));

  if (!dartLoaderFound) {
    document.body.nodes.add(parseFragment(
        '<script type="text/javascript" src="packages/browser/dart.js">'
        '</script>\n'));
  }

  // Insert the "auto-generated" comment after the doctype, otherwise IE will
  // go into quirks mode.
  int commentIndex = 0;
  DocumentType doctype = find(document.nodes, (n) => n is DocumentType);
  if (doctype != null) {
    commentIndex = document.nodes.indexOf(doctype) + 1;
    // TODO(jmesserly): the html5lib parser emits a warning for missing
    // doctype, but it allows you to put it after comments. Presumably they do
    // this because some comments won't force IE into quirks mode (sigh). See
    // this link for more info:
    //     http://bugzilla.validator.nu/show_bug.cgi?id=836
    // For simplicity we emit the warning always, like validator.nu does.
    if (doctype.tagName != 'html' || commentIndex != 1) {
      messages.warning('file should start with <!DOCTYPE html> '
          'to avoid the possibility of it being parsed in quirks mode in IE. '
          'See http://www.w3.org/TR/html5-diff/#doctype', doctype.sourceSpan);
    }
  }
  document.nodes.insert(commentIndex, parseFragment(
      '\n<!-- This file was auto-generated from $filePath. -->\n'));
}
