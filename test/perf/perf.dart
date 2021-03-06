// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * This is a helper for perf.sh. We try to run all of the Dart code in one
 * instance of the Dart VM to reduce warm-up time.
 */
library test.perf.perf;

import 'dart:async';
import 'dart:io';
import 'dart:json' as json;
import 'dart:utf' show encodeUtf8;
import 'dart:isolate';

import 'package:unittest/unittest.dart';
import 'package:unittest/compact_vm_config.dart';
import 'package:web_ui/dwc.dart' as dwc;


main() {
  var args = new Options().arguments;
  var pattern = new RegExp(args.length > 0 ? args[0] : '.');

  useCompactVMConfiguration();

  var lister = new Directory.fromPath(new Path('input')).list();
  var cwd = new Path(new Directory.current().path);
  var inputDir = cwd.append('input');
  var results = {};
  lister.onFile = (path) {
    if (!path.endsWith('_test.html') || !pattern.hasMatch(path)) return;
    var filename = new Path(path).filename;
    var outDir = cwd.append('output');
    var htmlPath = outDir.append(filename).toString();
    var dartPath = outDir.append('${filename}_bootstrap.dart').toString();

    test('drt-compile $filename', () {
      expect(dwc.run(['-o', 'output/', path], printTime: false)
        .then((res) {
          expect(res.messages.length, 0,
              reason: Strings.join(res.messages, '\n'));
        }), completes);
    });

    test('drt-run $filename', () {
      results['dart $filename'] = null;
      var outputPath = '$htmlPath.txt';
      expect(Process.run('DumpRenderTree', [htmlPath]).then((res) {
        results['dart $filename'] = _extractResult(res.stdout);
        expect(res.exitCode, 0, reason:
          'DumpRenderTree exited with a non-zero exit code, when running '
          'on $filename. Contents of stderr: \n${res.stderr}');
      }), completes);
    });

    test('dart2js-compile $filename', () {
      expect(Process.run('dart2js', ["-o$dartPath.js", dartPath]).then(
          (res) {
            if (res.stdout != null && res.stdout != '') print(res.stdout);
            expect(res.exitCode, 0, reason:
              'dart2js exited with a non-zero exit code, when running '
              'on $dartPath. Contents of stderr: \n${res.stderr}');
            }), completes);
    });

    test('js-drt-run $filename', () {
      results['js   $filename'] = null;
      // Create new .html file to ensure DRT runs the code as Javascript.
      var htmlJSPath = '${htmlPath}_js.html';
      var html = new File(htmlPath).readAsStringSync()
          .replaceAll(new RegExp('<script .*/start_dart.js"></script>'), '')
          .replaceAll(new RegExp('<script .*/dart.js"></script>'), '')
          .replaceAll('"application/dart"', '"application/javascript"')
          .replaceAll('.html_bootstrap.dart', '.html_bootstrap.dart.js');
      new File(htmlJSPath).writeAsStringSync(html);

      expect(Process.run('DumpRenderTree', [htmlJSPath]).then((res) {
        results['js   $filename'] = _extractResult(res.stdout);
        expect(res.exitCode, 0, reason:
          'DumpRenderTree exited with a non-zero exit code, when running '
          'on $filename. Contents of stderr: \n${res.stderr}');
      }), completes);
    });

    lister.onDone = (done) {
      test('printing-results', () {
        print('\nRESULTS');
        results.forEach((k, v) {
          print('  $k: $v');
        });
        expect(_writeFile('$cwd/output/results.json', json.stringify(results)),
          completes);
      });
    };
  };
}

final _SCORE_REGEX = new RegExp(r'^CONSOLE.*benchmark-score: (.*)$',
    multiLine: true);

_extractResult(String s) {
  var match = _SCORE_REGEX.firstMatch(s);
  return (match != null) ? double.parse(match.group(1)) : null;
}

Future _writeFile(String path, String text) {
  return new File(path).open(FileMode.WRITE)
      .then((file) => file.writeString(text))
      .then((file) => file.close());
}
