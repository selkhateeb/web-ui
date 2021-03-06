# changelog

This file contains highlights of what changes on each version of the web_ui
package. This file is normally updated whenever we push a new version to pub.

## Upcoming changes (next release)
  * Changes to use the new libraries (lib v2)
  * More readable output: generated code is more compact and easy to correlate
    with source templates
  * Making some declarations optional:
      * You can omit the script tag in the entry page, we will generate
        an empty one for you.
        **NOTE**: make sure you only put entrypoint html files in 'build.dart'.
        This change makes the compiler accept any html file (including files
        that only define components) and treat them as entrypoints.
        If you include a component's html file in build.dart, the compiler will
        generate additional files that you don't need.
      * Components with no 'extends' attribute extend from 'span' by default
  * bug fixes:
       * remove extra whitespace incorrectly inserted in components

## Pub version 0.2.11 - Jan 07 2013 (integration SDK r16761)
  * internal changes in code structure
  * fix for type errors with templates in SVG

## Pub version 0.2.10+2 - Dec 17 (integration SDK 16251)
  * Bug fix: build.dart kept running nonstop (wihtin the Editor) if you had components code under a subdirectory.

## Pub version 0.2.10, 0.2.10+1 - Dec 12 (integration SDK 16251)
  * Updates to comply with trunk SDK 16102 (part of next trunk release)

## Pub version 0.2.9 - Dec 11 (SDK 15948)
  * Updates to comply with all breaking changes in the new trunk SDK

## Pub version 0.2.8+6 - Dec 10 (SDK 15595, integration SDK 15699)

  * Bug fix:
    * No longer generates calls to Element constructors that don't exist
      (affected heading and strong elements, among others)

## Pub version 0.2.8+5 - Dec 7 (SDK 15595, integration SDK 15699)

  * Rename package to web_ui
  * Change TodoMVC to have component with composition
  * Bug fix:
    * fix component composition in Firefox (workaround dart:html matchesSelector)

## Pub version 0.2.8+4 - Dec 7 (trunk SDK 15595, integration SDK 15699)

  * Support for forwarding error messages and file mappings to the editor
  * Bug fixes:
    * errors in Firefox
    * allow including web-components from packages/...
    * fix --basedir
    * bugs with id when using nested components (component composition)

## Pub version 0.2.8+3 - Nov 30 (trunk SDK 15595, integration SDK 15699)

  * Upgrades for new trunk release (mainly breaking changes in dart:html)

## Pub version 0.2.8+2 - Nov 30 (trunk SDK 15355)

  * Bug fix:
    * hosted and sdk dependencies errors due to changes in html5lib.
    * URI attributes are now checked for XSS: use SafeUri if validation is too
      strict.

## Pub version 0.2.8+1 - Nov 30 (SDK 15355)

  * Accept, but ignore, the new editor flag '--machine' in build.dart 

## Pub version 0.2.8 - Nov 30 (SDK 15355)

  * Two-way binding changes:
    * New syntax: `bind-attribute="dartAssignableValue"`, `data-bind` is
      deprecated
    * Support for radio buttons
    * Support for valueAsDate and valueAsNumber
    * Better detection of error conditions, like duplicate value attributes.

  * Binding in components:
    * you can use `attribute="{{}}"` and `bind-attribute="x"` to initialize,
      update, and bind fields of components (exposed as attributes in the HTML
      tag).

  * Conditional templates:
    * Added new experimental syntax `<template if="exp">`.

  * Bug fixes:
    * Make dartium extension use the latest dart.js
    * html fragments: fix issues with text nodes mixed with elements
    * Internally data bindings watch the result of 'toString()', so types
      implementing toString (like Maps or StringBuffer) can be used directly in
      templates.
    * Most generated identifiers are now hidden: all identifiers generated for
      html elements in the template are hidden, except '_root'. Root will be
      hidden in the future.

## Pub version 0.2.7 - Nov 26 (SDK 15355)

  * New syntax for inline event handlers: `on-click="increment($event)"` instead
    of `data-action="click:increment"`
  * Added new explainer examples
  * Updated dartium extension
  * Bug fixes:
      * Support for querying for elements from main()
      * Recursive imports between components
      * Warnings are emitted (previously they were generated but not printed)
  
## Pub version 0.2.6+1 - 16 Nov 2012

  * Name mangling turned off if --out is specified
  * Support for `<select>` in data-bind

## Pub version 0.2.5+5

  * Bug fix: adds missing id on elements that we query in generated code

## Pub version 0.2.5+4

  * Bug fix: additional fixes for symlinks in windows

## Pub version 0.2.5+3

  * Fixes symlinks for windows
  * Support for composition and extension
  * Support for list and spaces in bindings of class attribtues
  * Simpliffications in generated code
  * Allow text bindings and fragments in conditions an iterations
  * Support text nodes and fragments at the top level of components

See git version tags for older changes.
