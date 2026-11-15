// スマホ用：最初のタッチで全画面＋横向き固定、端末を左右に振る（スイング）を「もがき」として数える。
(function () {
  if (!('ontouchstart' in window) && !(navigator.maxTouchPoints > 0)) return;
  var flips = 0, lastSign = 0, lastFlip = 0, hp = 0, prevRaw = 0;
  var TH = 7.0;          // これより強く振ったら1回（m/s²、重力抜き）
  function horiz(e) {
    var a = e.acceleration, x, y;
    if (a && a.x != null) { x = a.x; y = a.y; }
    else {
      // 重力込みしか取れない端末：ゆっくりした傾きを引いて、振った分だけ取り出す
      var g = e.accelerationIncludingGravity || {x: 0, y: 0};
      x = g.x; y = g.y;
    }
    var ang = (screen.orientation && screen.orientation.angle) || window.orientation || 0;
    ang = ((ang % 360) + 360) % 360;
    if (ang === 90) return y;
    if (ang === 270) return -y;
    if (ang === 180) return -x;
    return x;
  }
  function onMotion(e) {
    var raw = horiz(e);
    if (!(e.acceleration && e.acceleration.x != null)) { hp = 0.8 * (hp + raw - prevRaw); prevRaw = raw; raw = hp; }
    var now = performance.now();
    if (Math.abs(raw) > TH) {
      var s = raw > 0 ? 1 : -1;
      if (s !== lastSign && now - lastFlip > 90) { flips++; lastSign = s; lastFlip = now; }
    }
  }
  window.__swingTake = function () { var n = flips; flips = 0; return n; };
  var listening = false;
  function listen() { if (!listening) { listening = true; window.addEventListener('devicemotion', onMotion); } }
  if (typeof DeviceMotionEvent === 'undefined' || typeof DeviceMotionEvent.requestPermission !== 'function') listen();
  var asked = false;
  function gesture() {
    var el = document.documentElement;
    var fs = document.fullscreenElement || document.webkitFullscreenElement;
    if (!fs) {
      var req = el.requestFullscreen || el.webkitRequestFullscreen;
      if (req) {
        try {
          var r = req.call(el, {navigationUI: 'hide'});
          if (r && r.then) r.then(function () {
            if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function () {});
          }).catch(function () {});
        } catch (err) {}
      }
    }
    if (!asked && typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
      asked = true;
      DeviceMotionEvent.requestPermission().then(function (st) { if (st === 'granted') listen(); }).catch(function () {});
    }
  }
  document.addEventListener('touchend', gesture, {passive: true});
})();
