// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/** End-to-end tests for the [Compiler] API. */
library compiler_test;

import 'dart:async';
import 'dart:io';
import 'package:html5lib/dom.dart';
import 'package:logging/logging.dart' show Level;
import 'package:unittest/compact_vm_config.dart';
import 'package:unittest/unittest.dart';
import 'package:web_ui/src/compiler.dart';
import 'package:web_ui/src/file_system.dart';
import 'package:web_ui/src/options.dart';
import 'testing.dart';
import 'package:web_ui/src/messages.dart';

main() {
  useCompactVMConfiguration();

  var messages;

  Compiler createCompiler(Map files) {
    var options = CompilerOptions.parse([
        '--no-colors', '-o', 'out', 'index.html']);
    var fs = new MockFileSystem(files);
    messages = new Messages.silent();
    return new Compiler(fs, options, messages);
  }

  test('recursive dependencies', () {
    var compiler = createCompiler({
      'index.html': '<head>'
                    '<link rel="components" href="foo.html">'
                    '<link rel="components" href="bar.html">'
                    '<body><x-foo></x-foo><x-bar></x-bar>'
                    '<script type="application/dart">main() {}</script>',
      'foo.html': '<head><link rel="components" href="bar.html">'
                  '<body><element name="x-foo" constructor="Foo">'
                  '<template><x-bar>',
      'bar.html': '<head><link rel="components" href="foo.html">'
                  '<body><element name="x-bar" constructor="Boo">'
                  '<template><x-foo>',
    });

    compiler.run().then(expectAsync1((e) {
      MockFileSystem fs = compiler.fileSystem;
      expect(fs.readCount, equals({
        'index.html': 1,
        'foo.html': 1,
        'bar.html': 1
      }), reason: 'Actual:\n  ${fs.readCount}');

      var outputs = compiler.output.map((o) => o.path);
      expect(outputs, equals([
        'out/foo.html.dart',
        'out/foo.html.dart.map',
        'out/bar.html.dart',
        'out/bar.html.dart.map',
        'out/index.html.dart',
        'out/index.html.dart.map',
        'out/index.html_bootstrap.dart',
        'out/index.html',
      ]));
    }));
  });

  group('missing files', () {
    test('main script', () {
      var compiler = createCompiler({
        'index.html': '<head></head><body>'
            '<script type="application/dart" src="notfound.dart"></script>'
            '</body>',
      });

      compiler.run().then(expectAsync1((e) {
        var msgs = messages.messages.where((m) =>
            m.message.contains('notfound.dart')).toList();

        expect(msgs.length, 1);
        expect(msgs[0].level, Level.SEVERE);
        expect(msgs[0].message, contains('exception while reading file'));

        MockFileSystem fs = compiler.fileSystem;
        expect(fs.readCount, { 'index.html': 1, 'notfound.dart': 1 });

        var outputs = compiler.output.map((o) => o.path.toString());
        expect(outputs, []);
      }));
    });

    test('component html', () {
      var compiler = createCompiler({
        'index.html': '<head>'
            '<link rel="components" href="notfound.html">'
            '<body><x-foo>'
            '<script type="application/dart">main() {}</script>',
      });

      compiler.run().then(expectAsync1((e) {
        var msgs = messages.messages.where((m) =>
            m.message.contains('notfound.html')).toList();

        expect(msgs.length, 1);
        expect(msgs[0].level, Level.SEVERE);
        expect(msgs[0].message, contains('exception while reading file'));

        MockFileSystem fs = compiler.fileSystem;
        expect(fs.readCount, { 'index.html': 1, 'notfound.html': 1 });

        var outputs = compiler.output.map((o) => o.path.toString());
        expect(outputs, []);
      }));
    });

    test('component script', () {
      var compiler = createCompiler({
        'index.html': '<head>'
            '<link rel="components" href="foo.html">'
            '<body><x-foo></x-foo>'
            '<script type="application/dart">main() {}</script>'
            '</body>',
        'foo.html': '<body><element name="x-foo" constructor="Foo">'
            '<template></template>'
            '<script type="application/dart" src="notfound.dart"></script>',
      });

      compiler.run().then(expectAsync1((e) {
        var msgs = messages.messages.where((m) =>
            m.message.contains('notfound.dart')).toList();

        expect(msgs.length, 1);
        expect(msgs[0].level, Level.SEVERE);
        expect(msgs[0].message, contains('exception while reading file'));

        MockFileSystem fs = compiler.fileSystem;
        expect(fs.readCount,
            { 'index.html': 1, 'foo.html': 1, 'notfound.dart': 1  });

        var outputs = compiler.output.map((o) => o.path.toString());
        expect(outputs, []);
      }));
    });
  });
}

/**
 * Abstraction around file system access to work in a variety of different
 * environments.
 */
class MockFileSystem extends FileSystem {
  final Map _files;
  final Map readCount = {};

  MockFileSystem(this._files);

  Future readTextOrBytes(String filename) => readText(filename);

  Future<String> readText(String path) {
    readCount[path] = readCount.putIfAbsent(path, () => 0) + 1;
    var file = _files[path];
    if (file != null) {
      return new Future.immediate(file);
    } else {
      return new Future.immediateError(
          new FileIOException('MockFileSystem: $path not found'));
    }
  }

  // Compiler doesn't call these
  void writeString(String outfile, String text) {}
  Future flush() {}
}
