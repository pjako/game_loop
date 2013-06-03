/*
  Copyright (C) 2013 John McCutchan <john@johnmccutchan.com>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/

part of game_loop_html;

/** Called when it is time to draw. */
typedef void GameLoopRenderFunction(GameLoop gameLoop);

/** Called whenever the element is resized. */
typedef void GameLoopResizeFunction(GameLoop gameLoop);

/** Called whenever the element moves between fullscreen and non-fullscreen
 * mode.
 */
typedef void GameLoopFullscreenChangeFunction(GameLoop gameLoop);

/** Called whenever the element moves between locking the pointer and
 * not locking the pointer.
 */
typedef void GameLoopPointerLockChangeFunction(GameLoop gameLoop);

/** Called whenever a touch event begins */
typedef void GameLoopTouchEventFunction(GameLoop gameLoop, GameLoopTouch touch);

/** The game loop */
class GameLoopHtml extends GameLoop {
  final Element element;
  int _frameCounter = 0;
  bool _initialized = false;
  bool _interrupt = false;
  double _previousFrameTime;
  double _frameTime = 0.0;
  double get frameTime => _frameTime;
  bool _resizePending = false;
  double _nextResize = 0.0;


  double _interruptTime = 0.0;
  double _timeLost = 0.0;

  /** Seconds of accumulated time. */
  double get accumulatedTime => _accumulatedTime;

  /** Frame counter value. Incremented once per frame. */
  int get frame => _frameCounter;

  /** Current time. */
  double get time => GameLoop.timeStampToSeconds(
      window.performance.now());

  double maxAccumulatedTime = 0.03;
  double _accumulatedTime = 0.0;
  /** Width of game display [Element] */
  int get width => element.client.width;
  /** Height of game display [Element] */
  int get height => element.client.height;

  double _gameTime = 0.0;
  double get gameTime => _gameTime;

  double _renderInterpolationFactor = 0.0;
  double get renderInterpolationFactor => _renderInterpolationFactor;
  /** The minimum amount of time between two onResize calls in seconds*/
  double resizeLimit = 0.05;

  PointerLock _pointerLock;
  PointerLock get pointerLock => _pointerLock;

  Keyboard _keyboard;
  /** Keyboard. */
  Keyboard get keyboard => _keyboard;
  Mouse _mouse;
  /** Mouse. */
  Mouse get mouse => _mouse;
  GameLoopGamepad _gamepad0;
  Point _lastMousePos = new Point(0,0);
  /** Gamepad #0. */
  GameLoopGamepad get gamepad0 => _gamepad0;
  /** Touch */
  GameLoopTouchSet _touchSet;
  GameLoopTouchSet get touchSet => _touchSet;

  /** Construct a new game loop attaching it to [element] */
  GameLoopHtml(this.element) : super() {
    _keyboard = new Keyboard(this);
    _mouse = new Mouse(this);
    _gamepad0 = new GameLoopGamepad(this);
    _pointerLock = new PointerLock(this);
    _touchSet = new GameLoopTouchSet(this);
  }

  void _processInputEvents() {
    double currentVirtualTime = _gameTime + _timeLost;
    _processKeyboardEvents(currentVirtualTime);
    _processMouseEvents(currentVirtualTime);
    _processTouchEvents(currentVirtualTime);
  }

  void _processKeyboardEvents(double currentVirtualTime) {
    int idx = 0;
    for (;_keyboardEvents.length > idx; idx++) {
      double timeStamp = _keyboardEventTime[idx];
      if(currentVirtualTime < timeStamp) {
        idx--;
        break;
      }
      KeyboardEvent keyboardEvent = _keyboardEvents[idx];
      DigitalButtonEvent event;
      bool down = keyboardEvent.type == "keydown";
      double time = GameLoop.timeStampToSeconds(keyboardEvent.timeStamp);
      int buttonId = keyboardEvent.keyCode;
      event = new DigitalButtonEvent(buttonId, down, frame, time);
      _keyboard.digitalButtonEvent(event);
    }
    if (idx > 0) {
      _keyboardEvents.removeRange(0, idx);
      _keyboardEventTime.removeRange(0, idx);
    }
  }

  void _processMouseEvents(double currentVirtualTime) {
    mouse._resetAccumulators();
    // TODO(alexgann): Remove custom offset logic once dart:html supports natively (M6).
    final docElem = document.documentElement;
    final box = element.getBoundingClientRect();
    int canvasX = (box.left + window.pageXOffset - docElem.clientLeft).floor();
    int canvasY = (box.top  + window.pageYOffset - docElem.clientTop).floor();
    int idx = 0;
    for(;idx < _mouseEvents.length; idx++) {
      double timeStamp = _mouseEventTime[idx];
      if(currentVirtualTime < timeStamp) {
        idx--;
        break;
      }
      MouseEvent mouseEvent = _mouseEvents[idx];
      bool moveEvent = mouseEvent.type == 'mousemove';
      bool wheelEvent = mouseEvent.type == 'mousewheel';
      bool down = mouseEvent.type == 'mousedown';
      double time = GameLoop.timeStampToSeconds(mouseEvent.timeStamp);
      if (moveEvent) {
        int mouseX = mouseEvent.page.x;
        int mouseY = mouseEvent.page.y;
        int x = mouseX - canvasX;
        int y = mouseY - canvasY;
        int clampX = 0;
        int clampY = 0;
        bool withinCanvas = false;
        if(mouseX < canvasX) {
          clampX = 0;
        } else if(mouseX > canvasX+width) {
          clampX = width;
        } else {
          clampX = x;
          withinCanvas = true;
        }
        if(mouseY < canvasY) {
          clampY = 0;
          withinCanvas = false;
        } else if(mouseY > canvasY+height) {
          clampY = height;
          withinCanvas = false;
        } else {
          clampY = y;
        }

        int dx = mouseEvent.client.x-_lastMousePos.x;
        int dy = mouseEvent.client.y-_lastMousePos.y;
        _lastMousePos = mouseEvent.client;
        var event = new GameLoopMouseEvent(x, y, dx, dy, clampX, clampY, withinCanvas, time, frame);
        _mouse.gameLoopMouseEvent(event);
      } else if (wheelEvent) {
        WheelEvent wheel = mouseEvent as WheelEvent;
        _mouse._accumulateWheel(wheel.deltaX, wheel.deltaY);
      } else {
        int buttonId = mouseEvent.button;
        var event = new DigitalButtonEvent(buttonId, down, frame, time);
        _mouse.digitalButtonEvent(event);
      }
    }
    if (idx > 0) {
      _mouseEvents.removeRange(0, idx);
      _mouseEventTime.removeRange(0, idx);
    }
  }

  void _processTouchEvents(double currentVirtualTime) {
    int idx = 0;
    for(; idx < _touchEvents.length; idx++) {
      _GameLoopTouchEvent touchEvent = _touchEvents[idx];
      if(touchEvent.time > currentVirtualTime) {
        idx--;
        break;
      }
      touchEvent = _touchEvents[idx];
      switch (touchEvent.type) {
        case _GameLoopTouchEvent.Start:
          _touchSet._start(touchEvent.event);
          break;
        case _GameLoopTouchEvent.End:
          _touchSet._end(touchEvent.event);
          break;
        case _GameLoopTouchEvent.Move:
          _touchSet._move(touchEvent.event);
          break;
        default:
          throw new StateError('Invalid _GameLoopTouchEven type.');
      }
    }
    if (idx > 0) {
      _touchEvents.removeRange(0, idx-1);
    }
  }

  int _rafId;

  void _requestAnimationFrame(num _) {
    if (_previousFrameTime == null) {
      _frameTime = time;
      _previousFrameTime = _frameTime;
      _processInputEvents();
      _rafId = window.requestAnimationFrame(_requestAnimationFrame);
      return;
    }
    if (_interrupt == true) {
      _rafId = null;
      return;
    }
    _rafId = window.requestAnimationFrame(_requestAnimationFrame);
    _frameCounter++;
    _previousFrameTime = _frameTime;
    _frameTime = time;
    double timeDelta = _frameTime - _previousFrameTime;
    _accumulatedTime += timeDelta;
    if (_accumulatedTime > maxAccumulatedTime) {
      _timeLost += _accumulatedTime - maxAccumulatedTime;
      // If the animation frame callback was paused we may end up with
      // a huge time delta. Clamp it to something reasonable.
      _accumulatedTime = maxAccumulatedTime;
    }
    // TODO(johnmccutchan): Process input events in update loop.
    _processInputEvents();
    while (_accumulatedTime >= updateTimeStep) {
      processTimers();
      _gameTime += updateTimeStep;
      if (onUpdate != null) {
        onUpdate(this);
      }
      _accumulatedTime -= updateTimeStep;
    }
    if(_resizePending == true && onResize != null && _nextResize <= _frameTime){
      onResize(this);
      _nextResize = _frameTime + resizeLimit;
      _resizePending = false;
    }

    if (onRender != null) {
      _renderInterpolationFactor = _accumulatedTime/updateTimeStep;
      onRender(this);
    }
  }

  void _fullscreenChange(Event _) {
    if (onFullscreenChange == null) {
      return;
    }
    onFullscreenChange(this);
  }

  void _fullscreenError(Event _) {
    if (onFullscreenChange == null) {
      return;
    }
    onFullscreenChange(this);
  }

  final List<_GameLoopTouchEvent> _touchEvents = new List<_GameLoopTouchEvent>();
  void _touchStartEvent(TouchEvent event) {
    _touchEvents.add(new _GameLoopTouchEvent(event, _GameLoopTouchEvent.Start,
        time));
  }
  void _touchMoveEvent(TouchEvent event) {
    _touchEvents.add(new _GameLoopTouchEvent(event, _GameLoopTouchEvent.Move,
        time));
  }
  void _touchEndEvent(TouchEvent event) {
    _touchEvents.add(new _GameLoopTouchEvent(event, _GameLoopTouchEvent.End,
        time));
  }

  final List<KeyboardEvent> _keyboardEvents = new List<KeyboardEvent>();
  final List<double> _keyboardEventTime = new List<double>();
  void _keyDown(KeyboardEvent event) {
    _keyboardEvents.add(event);
    _keyboardEventTime.add(time);
  }

  void _keyUp(KeyboardEvent event) {
    _keyboardEvents.add(event);
    _keyboardEventTime.add(time);
  }

  final List<MouseEvent> _mouseEvents = new List<MouseEvent>();
  final List<double> _mouseEventTime = new List<double>();
  void _mouseDown(MouseEvent event) {
    _mouseEvents.add(event);
    _mouseEventTime.add(time);
  }

  void _mouseUp(MouseEvent event) {
    _mouseEvents.add(event);
    _mouseEventTime.add(time);
  }

  void _mouseMove(MouseEvent event) {
    _mouseEvents.add(event);
    _mouseEventTime.add(time);
  }

  void _mouseWheel(MouseEvent event) {
    _mouseEvents.add(event);
    _mouseEventTime.add(time);
    event.preventDefault();
  }

  void _resize(Event _) {
    if (_resizePending == false) {
      _resizePending = true;
    }
  }

  /** Start the game loop. */
  void start() {
    if (_initialized == false) {
      document.onFullscreenError.listen(_fullscreenError);
      document.onFullscreenChange.listen(_fullscreenChange);
      window.onTouchStart.listen(_touchStartEvent);
      window.onTouchEnd.listen(_touchEndEvent);
      window.onTouchMove.listen(_touchMoveEvent);
      window.onKeyDown.listen(_keyDown);
      window.onKeyUp.listen(_keyUp);
      window.onResize.listen(_resize);

      window.onMouseMove.listen(_mouseMove);
      window.onMouseDown.listen(_mouseDown);
      window.onMouseUp.listen(_mouseUp);
      window.onMouseWheel.listen(_mouseWheel);
      _initialized = true;
    }
    _timeLost += time - _interruptTime;
    _interrupt = false;
    _rafId = window.requestAnimationFrame(_requestAnimationFrame);
  }

  /** Stop the game loop. */
  void stop() {
    if (_rafId != null) {
      window.cancelAnimationFrame(_rafId);
      _rafId = null;
    }
    _interrupt = true;
    _interruptTime = time;
  }

  /** Is the element visible on the screen? */
  bool get isVisible => document.visibilityState == 'visible' && element.hidden == false;

  /** Is the element being displayed full screen? */
  bool get isFullscreen => document.fullscreenElement == element;

  /** Enable or disable fullscreen display of the element. */
  void enableFullscreen(bool enable) {
    if (enable) {
      element.requestFullscreen();
      return;
    }
    document.exitFullscreen();
  }

  /** Called when it is time to draw. */
  GameLoopRenderFunction onRender;

  /** Called when element is resized. */
  GameLoopResizeFunction onResize;
  /** Called when element enters or exits fullscreen mode. */
  GameLoopFullscreenChangeFunction onFullscreenChange;
  /** Called when the element moves between owning and not
   *  owning the pointer.
   */
  GameLoopPointerLockChangeFunction onPointerLockChange;
  /** Called when a touch begins. */
  GameLoopTouchEventFunction onTouchStart;
  /** Callled when a touch ends. */
  GameLoopTouchEventFunction onTouchEnd;
}
