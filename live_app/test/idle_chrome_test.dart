import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/idle_chrome_controller.dart';

/// Short delays keep the suite fast; the semantics under test are the same.
const _idle = Duration(milliseconds: 30);
const _hint = Duration(milliseconds: 30);

IdleChromeController controller({bool Function()? canRetire}) =>
    IdleChromeController(
      canRetire: canRetire ?? () => true,
      idleDelay: _idle,
      hintDuration: _hint,
    );

Future<void> waitPast(Duration duration) =>
    Future<void>.delayed(duration + const Duration(milliseconds: 25));

void main() {
  test('controls stay up until the ride has been left alone', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    expect(chrome.visible, isTrue);
    await waitPast(_idle);
    expect(chrome.visible, isFalse);
  });

  test('a touch brings the controls back immediately', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    await waitPast(_idle);
    expect(chrome.visible, isFalse);

    chrome.wake();
    expect(chrome.visible, isTrue);
  });

  test('every touch postpones the quiet', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      chrome.wake();
      expect(chrome.visible, isTrue);
    }

    await waitPast(_idle);
    expect(chrome.visible, isFalse);
  });

  test('notifies the screen when it retires and when it returns', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    var notifications = 0;
    chrome.addListener(() => notifications++);

    await waitPast(_idle);
    expect(notifications, 1);

    chrome.wake();
    expect(notifications, 2);
  });

  test('a paused ride keeps its controls', () async {
    var recording = false;
    final chrome = controller(canRetire: () => recording)..restart();
    addTearDown(chrome.dispose);

    await waitPast(_idle);
    expect(chrome.visible, isTrue);

    recording = true;
    chrome.restart();
    await waitPast(_idle);
    expect(chrome.visible, isFalse);
  });

  test(
    'a ride that pauses after the countdown started stays visible',
    () async {
      var recording = true;
      final chrome = controller(canRetire: () => recording)..restart();
      addTearDown(chrome.dispose);

      recording = false;
      await waitPast(_idle);
      expect(chrome.visible, isTrue);
    },
  );

  test('an open sheet pins the controls open', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    chrome.hold();
    await waitPast(_idle);
    expect(chrome.visible, isTrue);
    expect(chrome.isHeld, isTrue);

    chrome.release();
    expect(chrome.isHeld, isFalse);
    await waitPast(_idle);
    expect(chrome.visible, isFalse);
  });

  test('nested holds do not release each other early', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    chrome
      ..hold()
      ..hold()
      ..release();

    await waitPast(_idle);
    expect(chrome.visible, isTrue);

    chrome.release();
    await waitPast(_idle);
    expect(chrome.visible, isFalse);
  });

  test('the gesture hint appears once and then never again', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    await waitPast(_idle);
    expect(chrome.hintVisible, isTrue);
    expect(chrome.hintUsed, isTrue);

    await waitPast(_hint);
    expect(chrome.hintVisible, isFalse);
    expect(chrome.visible, isFalse);

    chrome.wake();
    await waitPast(_idle);
    expect(chrome.visible, isFalse);
    expect(chrome.hintVisible, isFalse);
  });

  test('waking clears a hint that is still on screen', () async {
    final chrome = controller()..restart();
    addTearDown(chrome.dispose);

    await waitPast(_idle);
    expect(chrome.hintVisible, isTrue);

    chrome.wake();
    expect(chrome.hintVisible, isFalse);
    expect(chrome.visible, isTrue);
  });

  test('a disposed controller stops scheduling work', () async {
    final chrome = controller()..restart();
    chrome.dispose();

    await waitPast(_idle);
    expect(chrome.visible, isTrue);
  });
}
