// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * These are not quite unit tests, since we build on top of the analyzer and the
 * html5parser to build the input for each test.
 */
library emitter_test;

import 'package:html5lib/dom.dart';
import 'package:unittest/compact_vm_config.dart';
import 'package:unittest/unittest.dart';
import 'package:web_ui/src/analyzer.dart';
import 'package:web_ui/src/code_printer.dart';
import 'package:web_ui/src/emitters.dart';
import 'package:web_ui/src/html5_utils.dart';
import 'package:web_ui/src/info.dart';
import 'package:web_ui/src/file_system/path.dart' show Path;
import 'testing.dart';

main() {
  useCompactVMConfiguration();
  group('emit element field', () {
    group('declaration', () {
      test('no data binding', () {
        var tree = '<div></div>';
        expect(_declarations(tree), equals(''));
      });

      test('id only, no data binding', () {
        var tree = '<div id="one"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __one;'));
        expect(_declarations(tree, isClass: false), equals('var __one;'));
      });

      test('action with no id', () {
        var tree = '<div data-action="foo:bar"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __e0;'));
        expect(_declarations(tree, isClass: false), equals('var __e0;'));
      });

      test('action with id', () {
        var tree = '<div id="my-id" data-action="foo:bar"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __myId;'));
        expect(_declarations(tree, isClass: false), equals('var __myId;'));
      });

      test('1 way binding with no id', () {
        var tree = '<div foo="{{bar}}"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __e0;'));
        expect(_declarations(tree, isClass: false), equals('var __e0;'));
      });

      test('1 way binding with id', () {
        var tree = '<div id="my-id" foo="{{bar}}"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __myId;'));
        expect(_declarations(tree, isClass: false), equals('var __myId;'));
      });

      test('1 way class binding with no id', () {
        var tree = '<div class="{{bar}}"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __e0;'));
        expect(_declarations(tree, isClass: false), equals('var __e0;'));
      });

      test('1 way class binding with id', () {
        var tree = '<div id="my-id" class="{{bar}}"></div>';
        expect(_declarations(tree), equals('autogenerated.DivElement __myId;'));
        expect(_declarations(tree, isClass: false), equals('var __myId;'));
      });

      test('2 way binding with no id', () {
        var tree = '<input data-bind="value:bar"></input>';
        expect(_declarations(tree),
            equals('autogenerated.InputElement __e0;'));
        expect(_declarations(tree, isClass: false), equals('var __e0;'));
      });

      test('2 way binding with id', () {
        var tree = '<input id="my-id" data-bind="value:bar"></input>';
        expect(_declarations(tree),
            equals('autogenerated.InputElement __myId;'));
        expect(_declarations(tree, isClass: false), equals('var __myId;'));
      });

      test('1 way binding in content with no id', () {
        var tree = '<div>{{bar}}</div>';
        expect(_declarations(tree), 'autogenerated.DivElement __e1;');
        expect(_declarations(tree, isClass: false), equals('var __e1;'));
      });

      test('1 way binding in content with id', () {
        var tree = '<div id="my-id">{{bar}}</div>';
        expect(_declarations(tree), 'autogenerated.DivElement __myId;');
        expect(_declarations(tree, isClass: false), equals('var __myId;'));
      });
    });

    group('init', () {
      test('no data binding', () {
        var elem = parseSubtree('<div></div>');
        expect(_created(elem), equals(''));
      });

      test('id only, no data binding', () {
        var elem = parseSubtree('<div id="one"></div>');
        expect(_created(elem), equals("__one = _root.query('#one');"));
      });

      test('id only, no data binding', () {
        var elem = parseSubtree('<div id="one"></div>');
        expect(_init(elem), equals("__one = _root.query('#one');"));
      });

      test('action with no id', () {
        var elem = parseSubtree('<div data-action="foo:bar"></div>');
        expect(_init(elem), equals("__e0 = _root.query('#__e-0');"));
      });

      test('action with id', () {
        var elem = parseSubtree('<div id="my-id" data-action="foo:bar"></div>');
        expect(_init(elem), equals("__myId = _root.query('#my-id');"));
      });

      test('1 way binding with no id', () {
        var elem = parseSubtree('<div class="{{bar}}"></div>');
        expect(_init(elem), equals("__e0 = _root.query('#__e-0');"));
      });

      test('1 way binding with id', () {
        var elem = parseSubtree('<div id="my-id" class="{{bar}}"></div>');
        expect(_init(elem), equals("__myId = _root.query('#my-id');"));
      });

      test('2 way binding with no id', () {
        var elem = parseSubtree('<input data-bind="value:bar"></input>');
        expect(_init(elem), equals("__e0 = _root.query('#__e-0');"));
      });

      test('2 way binding with id', () {
        var elem = parseSubtree(
          '<input id="my-id" data-bind="value:bar"></input>');
        expect(_init(elem), equals("__myId = _root.query('#my-id');"));
      });

      test('sibling of a data-bound text node, with id and children', () {
        var elem = parseSubtree('<div id="a1">{{x}}<div id="a2">a</div></div>');
        expect(_init(elem, child: 1),
            "__a2 = new autogenerated.Element.html('<div id=\"a2\">a</div>');");
      });
    });

    group('type', () {
      htmlElementNames.forEach((tag, className) {
        // Skip script and body tags, we don't create fields for them.
        if (tag == 'script' || tag == 'body') return;

        test('$tag -> $className', () {
          var elem = new Element(tag)..attributes['class'] = "{{bar}}";
          expect(_declarationsForElem(elem),
              equals('autogenerated.$className __e0;'));
        });
      });
    });
  });

  group('emit text node field', () {
    test('declaration', () {
      var tree = '<div>{{bar}}</div>';
      expect(_declarations(tree, child: 0), '');
    });

    test('created', () {
      var elem = parseSubtree('<div>{{bar}}</div>');
      expect(_created(elem, child: 0),
          r"var __binding0 = __t.contentBind(() => (bar));");
    });
  });

  group('emit event listeners', () {
    test('created', () {
      var elem = parseSubtree('<div data-action="foo:bar"></div>');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          r'__t.listen(__e0.on.foo, ($event) { bar($event); });'));
    });

    test('created for input value data bind', () {
      var elem = parseSubtree('<input data-bind="value:bar"></input>');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          r'__t.listen(__e0.on.input, ($event) { bar = __e0.value; }); '
          r'__t.oneWayBind(() => (bar), (e) { __e0.value = e; }, false); '));
    });
  });

  group('emit data binding watchers for attributes', () {
    test('created', () {
      var elem = parseSubtree('<div foo="{{bar}}"></div>');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          "__t.oneWayBind(() => (bar), (e) { "
              "__e0.attributes['foo'] = e; }, false);"));
    });

    test('created for 1-way binding with dom accessor', () {
      var elem = parseSubtree('<input value="{{bar}}">');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          "__t.oneWayBind(() => (bar), (e) { __e0.value = e; }, false);"));
    });

    test('created for 2-way binding with dom accessor', () {
      var elem = parseSubtree('<input data-bind="value:bar">');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          r'__t.listen(__e0.on.input, ($event) { bar = __e0.value; }); '
          r'__t.oneWayBind(() => (bar), (e) { __e0.value = e; }, false); '));
    });

    test('created for data attribute', () {
      var elem = parseSubtree('<div data-foo="{{bar}}"></div>');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          "__t.oneWayBind(() => (bar), (e) { "
          "__e0.attributes['data-foo'] = e; }, false);"));
    });

    test('created for class', () {
      var elem = parseSubtree('<div class="{{bar}} {{foo}}" />');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          "__t.bindClass(__e0, () => (bar)); "
          "__t.bindClass(__e0, () => (foo));"));
    });

    test('created for style', () {
      var elem = parseSubtree('<div data-style="bar"></div>');
      expect(_created(elem), equalsIgnoringWhitespace(
          r"__e0 = _root.query('#__e-0'); "
          '__t.bindStyle(__e0, () => (bar));'));
    });
  });

  group('emit data binding watchers for content', () {

    test('declaration', () {
      var tree = '<div>fo{{bar}}o</div>';
      expect(_declarations(tree, child: 1), '');
    });

    test('created', () {
      var elem = parseSubtree('<div>fo{{bar}}o</div>');
      expect(_created(elem, child: 1),
        r"var __binding0 = __t.contentBind(() => (bar));");
    });
  });

  group('emit main page class', () {

    test('external resource URLs', () {
      var html =
          '<html><head>'
          '<script src="http://ex.com/a.js" type="text/javascript"></script>'
          '<script src="//example.com/a.js" type="text/javascript"></script>'
          '<script src="/a.js" type="text/javascript"></script>'
          '<link href="http://example.com/a.css" rel="stylesheet">'
          '<link href="//example.com/a.css" rel="stylesheet">'
          '<link href="/a.css" rel="stylesheet">'
          '</head><body></body></html>';
      var doc = parseDocument(html);
      var fileInfo = analyzeNodeForTesting(doc);
      fileInfo.userCode = new DartCodeInfo('main', null, [], '');
      var pathInfo = new PathInfo(new Path('a'), new Path('b'), true);

      var emitter = new MainPageEmitter(fileInfo);
      emitter.run(doc, pathInfo);
      expect(doc.outerHTML, equals(html));
    });

    group('transform css urls', () {

      var html = '<html><head>'
          '<link href="a.css" rel="stylesheet">'
          '</head><body></body></html>';

      test('html at the top level', () {
        var doc = parseDocument(html);
        var fileInfo = analyzeNodeForTesting(doc, filepath: 'a.html');
        fileInfo.userCode = new DartCodeInfo('main', null, [], '');
        // Issue #207 happened because we used to mistakenly take the path of
        // the external file when transforming the urls in the html file.
        fileInfo.externalFile = new Path('dir/a.dart');
        var pathInfo = new PathInfo(new Path(''), new Path('out'), true);
        var emitter = new MainPageEmitter(fileInfo);
        emitter.run(doc, pathInfo);
        expect(doc.outerHTML, html.replaceAll('a.css', '../a.css'));
      });

      test('file within dir -- base dir match input file dir', () {
        var doc = parseDocument(html);
        var fileInfo = analyzeNodeForTesting(doc, filepath: 'dir/a.html');
        fileInfo.userCode = new DartCodeInfo('main', null, [], '');
        // Issue #207 happened because we used to mistakenly take the path of
        // the external file when transforming the urls in the html file.
        fileInfo.externalFile = new Path('dir/a.dart');
        var pathInfo = new PathInfo(new Path('dir/'), new Path('out'), true);
        var emitter = new MainPageEmitter(fileInfo);
        emitter.run(doc, pathInfo);
        expect(doc.outerHTML, html.replaceAll('a.css', '../dir/a.css'));
      });

      test('file within dir, base dir at top-level', () {
        var doc = parseDocument(html);
        var fileInfo = analyzeNodeForTesting(doc, filepath: 'dir/a.html');
        fileInfo.userCode = new DartCodeInfo('main', null, [], '');
        // Issue #207 happened because we used to mistakenly take the path of
        // the external file when transforming the urls in the html file.
        fileInfo.externalFile = new Path('dir/a.dart');
        var pathInfo = new PathInfo(new Path(''), new Path('out'), true);
        var emitter = new MainPageEmitter(fileInfo);
        emitter.run(doc, pathInfo);
        expect(doc.outerHTML, html.replaceAll('a.css', '../../dir/a.css'));
      });
    });
  });
}

_init(Element elem, {int child}) {
  var info = analyzeElement(elem);
  var printer = new CodePrinter();
  if (child != null) {
    info = info.children[child];
  }
  emitInitializations(info, printer, new CodePrinter());
  return printer.toString().trim();
}

_created(Element elem, {int child}) {
  return _recurse(elem, true, child).printer.toString().trim();
}

_declarations(String tree, {bool isClass: true, int child}) {
  return _recurse(parseSubtree(tree), isClass, child)
      .declarations.formatString().trim();
}

_declarationsForElem(Element elem, {bool isClass: true, int child}) {
  return _recurse(elem, isClass, child).declarations.formatString().trim();
}

Context _recurse(Element elem, bool isClass, int child) {
  var info = analyzeElement(elem);
  var context = new Context(isClass: isClass);
  if (child != null) {
    info = info.children[child];
  }
  new RecursiveEmitter(null, context).visit(info);
  return context;
}
