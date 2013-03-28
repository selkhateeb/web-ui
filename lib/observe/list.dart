// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library web_ui.observe.list;

import 'dart:collection';
import 'observable.dart';
import 'package:web_ui/observe/utils.dart' show Arrays;

// TODO(jmesserly): this should extend the real list implementation.
// See http://dartbug.com/2600. The workaround was to copy+paste lots of code
// from the VM.
/**
 * Represents an observable list of model values. If any items are added,
 * removed, or replaced, then observers that are registered with
 * [observe] will be notified.
 */
class ObservableList<E> extends Collection<E> implements List<E>, Observable {
  // TODO(jmesserly): replace with mixin!
  final int hashCode = ++Observable.$_nextHashCode;
  var $_observers;
  List $_changes;

  /** The inner [List<E>] with the actual storage. */
  final List<E> _list;

  /**
   * Creates an observable list of the given [length].
   *
   * If no [length] argument is supplied an extendable list of
   * length 0 is created.
   *
   * If a [length] argument is supplied, a fixed size list of that
   * length is created.
   */
  ObservableList([int length])
      : _list = length != null ? new List<E>(length) : <E>[];

  /**
   * Creates an observable list with the elements of [other]. The order in
   * the list will be the order provided by the iterator of [other].
   */
  factory ObservableList.from(Iterable<E> other) =>
      new ObservableList<E>()..addAll(other);

  Iterator<E> get iterator => new ListIterator<E>(this);

  int get length {
    if (observeReads) notifyRead(this, ChangeRecord.FIELD, 'length');
    return _list.length;
  }

  set length(int value) {
    int len = _list.length;
    if (len == value) return;

    // Produce notifications if needed
    if (hasObservers(this)) {
      if (value < len) {
        // Remove items, then adjust length. Note the reverse order.
        for (int i = len - 1; i >= value; i--) {
          notifyChange(this, ChangeRecord.REMOVE, i, _list[i], null);
        }
        notifyChange(this, ChangeRecord.FIELD, 'length', len, value);
      } else {
        // Adjust length then add items
        notifyChange(this, ChangeRecord.FIELD, 'length', len, value);
        for (int i = len; i < value; i++) {
          notifyChange(this, ChangeRecord.INSERT, i, null, null);
        }
      }
    }

    _list.length = value;
  }

  E operator [](int index) {
    if (observeReads) notifyRead(this, ChangeRecord.INDEX, index);
    return _list[index];
  }

  operator []=(int index, E value) {
    var oldValue = _list[index];
    if (hasObservers(this)) {
      notifyChange(this, ChangeRecord.INDEX, index, oldValue, value);
    }
    _list[index] = value;
  }

  void add(E value) {
    int len = _list.length;
    if (hasObservers(this)) {
      notifyChange(this, ChangeRecord.FIELD, 'length', len, len + 1);
      notifyChange(this, ChangeRecord.INSERT, len, null, value);
    }

    _list.add(value);
  }

  // TODO(jmesserly): removeRange and insertRange will cause duplicate
  // notifcations for insert/remove in the middle. The first will be for the
  // insert/remove and the second will be for the array move. Also, setting
  // length happens after the insert/remove notifcation. I think this is
  // probably unavoidable because of how arrays work: if you insert/remove in
  // the middle you effectively change elements throughout the array.
  // Maybe we need a ChangeRecord.MOVE?

  void removeRange(int start, int length) {
    if (length == 0) return;

    Arrays.rangeCheck(this, start, length);
    if (hasObservers(this)) {
      for (int i = start; i < length; i++) {
        notifyChange(this, ChangeRecord.REMOVE, i, this[i], null);
      }
    }
    Arrays.copy(this, start + length, this, start,
        this.length - length - start);

    this.length = this.length - length;
  }

  void insertRange(int start, int length, [E initialValue]) {
    if (length == 0) return;
    if (length < 0) {
      throw new ArgumentError("invalid length specified $length");
    }
    if (start < 0 || start > this.length) throw new RangeError.value(start);

    if (hasObservers(this)) {
      for (int i = start; i < length; i++) {
        notifyChange(this, ChangeRecord.INSERT, i, null, initialValue);
      }
    }

    var oldLength = this.length;
    this.length = oldLength + length;  // Will expand if needed.
    Arrays.copy(this, start, this, start + length, oldLength - start);
    for (int i = start; i < start + length; i++) {
      this[i] = initialValue;
    }
  }

  // ---------------------------------------------------------------------------
  // Note: below this comment, methods are either:
  //   * redirect to Arrays
  //   * redirect to Collections
  //   * copy+paste from VM GrowableObjectArray.
  // The general idea is to have these methods operate in terms of our primitive
  // methods above, so they correctly track reads/writes.
  // ---------------------------------------------------------------------------

  bool remove(E item) {
    int i = indexOf(item);
    if (i == -1) return false;
    removeAt(i);
    return true;
  }

  void insert(int index, E item) => insertRange(index, 1, item);

  bool contains(E item) => IterableMixinWorkaround.contains(_list, item);

  E get first => this[0];

  E removeLast() {
    var len = length - 1;
    var elem = this[len];
    length = len;
    return elem;
  }

  int indexOf(E element, [int start = 0]) =>
      IterableMixinWorkaround.indexOfList(this, element, start);

  int lastIndexOf(E element, [int start]) =>
      IterableMixinWorkaround.lastIndexOfList(this, element, start);

  ObservableList<E> getRange(int start, int length) =>
      sublist(start, start + length);

  ObservableList<E> sublist(int start, [int end]) {
    if (end == null) end = length;
    var len = end - start;
    if (len == 0) return new ObservableList<E>(0);
    Arrays.rangeCheck(this, start, len);
    List list = new ObservableList<E>(len);
    Arrays.copy(this, start, list, 0, len);
    return list;
  }

  bool get isEmpty => length == 0;

  E get last => this[length - 1];

  void addLast(E value) => add(value);

  void sort([compare = Comparable.compare]) =>
      IterableMixinWorkaround.sortList(this, compare);

  Iterable<E> get reversed => IterableMixinWorkaround.reversedList(this);

  void clear() {
    this.length = 0;
  }

  E removeAt(int index) {
    E result = this[index];
    removeRange(index, 1);
    return result;
  }

  void setRange(int start, int length, List<E> from, [int startFrom = 0]) {
    IterableMixinWorkaround.setRangeList(this, start, length, from, startFrom);
  }

  Map<int, E> asMap() => IterableMixinWorkaround.asMapList(this);

  String toString() => Collections.collectionToString(this);
}

// TODO(jmesserly): copy+paste from collection-dev
/**
 * Iterates over a [List] in growing index order.
 */
class ListIterator<E> implements Iterator<E> {
  final List<E> _list;
  final int _length;
  int _position;
  E _current;

  ListIterator(List<E> list)
      : _list = list, _position = -1, _length = list.length;

  bool moveNext() {
    if (_list.length != _length) {
      throw new ConcurrentModificationError(_list);
    }
    int nextPosition = _position + 1;
    if (nextPosition < _length) {
      _position = nextPosition;
      _current = _list[nextPosition];
      return true;
    }
    _current = null;
    return false;
  }

  E get current => _current;
}
